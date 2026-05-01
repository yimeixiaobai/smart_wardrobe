import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import os.log

actor BackgroundRemovalService {
    static let shared = BackgroundRemovalService()

    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    private let logger = Logger(subsystem: "SmartWardrobe", category: "BackgroundRemoval")

    enum RemovalError: LocalizedError {
        case noSubject
        case processingFailed(String)
        case imageConversionFailed

        var errorDescription: String? {
            switch self {
            case .noSubject: return "未检测到前景物体"
            case .processingFailed(let msg): return "处理失败: \(msg)"
            case .imageConversionFailed: return "图片转换失败"
            }
        }
    }

    // MARK: - Public API

    /// 去背景结果（包含完整和裁剪两个版本，用于精修编辑器）
    struct DetailedResult {
        let trimmed: UIImage       // 裁剪后（用于预览/保存）
        let untrimmed: UIImage     // 未裁剪（与 resizedOriginal 像素对齐）
        let resizedOriginal: UIImage // 缩放后的原图（与 untrimmed 尺寸一致）
    }

    func removeBackground(from image: UIImage) async throws -> UIImage {
        let result = try await removeBackgroundDetailed(from: image)
        return result.trimmed
    }

    private static let maxDimension = 2048
    private static let maxPixelMemoryMB = 128

    func removeBackgroundDetailed(from image: UIImage) async throws -> DetailedResult {
        let oriented = image.fixedOrientation()
        guard let cgImage = oriented.cgImage else {
            throw RemovalError.imageConversionFailed
        }

        let inputCG = resizeIfNeeded(cgImage, maxDimension: Self.maxDimension)

        let estimatedMB = (inputCG.width * inputCG.height * 4 * 3) / (1024 * 1024)
        if estimatedMB > Self.maxPixelMemoryMB {
            throw RemovalError.processingFailed("图片过大（预估 \(estimatedMB)MB），请裁剪后重试")
        }
        let inputCI = CIImage(cgImage: inputCG)
        let resizedOrig = UIImage(cgImage: inputCG)

        // 尝试各策略，保留未裁剪版本
        let strategies: [(String, () throws -> CIImage)] = [
            ("VNGenerateForegroundInstanceMaskRequest", { try self.generateForegroundMask(for: inputCG) }),
            ("PersonSegmentation", { try self.generatePersonMask(for: inputCG, targetExtent: inputCI.extent) }),
            ("Saliency", { try self.generateSaliencyMask(for: inputCG, targetExtent: inputCI.extent) }),
            ("SafeColorMask", { try self.generateSafeColorMask(for: inputCG) }),
        ]

        for (name, generate) in strategies {
            do {
                let maskCI = try generate()
                logger.info("✅ 使用 \(name) 成功")
                let untrimmed = applyMask(maskCI, to: inputCI)
                let trimmed = trimToOpaqueArea(untrimmed)
                return DetailedResult(trimmed: trimmed, untrimmed: untrimmed, resizedOriginal: resizedOrig)
            } catch {
                logger.warning("⚠️ \(name) 失败: \(error.localizedDescription)")
            }
        }

        logger.error("❌ 所有去背景策略均失败，返回原图")
        return DetailedResult(trimmed: oriented, untrimmed: oriented, resizedOriginal: resizedOrig)
    }

    // MARK: - Apply Mask & Composite

    private func applyMask(_ mask: CIImage, to image: CIImage) -> UIImage {
        let feathered = mask
            .applyingGaussianBlur(sigma: 0.5)
            .cropped(to: image.extent)

        let transparent = CIImage(color: .clear).cropped(to: image.extent)
        let composited = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: transparent,
            kCIInputMaskImageKey: feathered
        ])

        guard let outputCG = ciContext.createCGImage(
            composited,
            from: composited.extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            return UIImage(ciImage: image)
        }

        return UIImage(cgImage: outputCG)
    }

    // MARK: - Strategy 1: VNGenerateForegroundInstanceMaskRequest (iOS 17+)

    private func generateForegroundMask(for cgImage: CGImage) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw RemovalError.noSubject
        }

        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )

        return CIImage(cvPixelBuffer: maskBuffer)
    }

    // MARK: - Strategy 2: PersonSegmentation

    private func generatePersonMask(for cgImage: CGImage, targetExtent: CGRect) throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw RemovalError.noSubject
        }

        let maskCI = CIImage(cvPixelBuffer: result.pixelBuffer)
        let scaleX = targetExtent.width / maskCI.extent.width
        let scaleY = targetExtent.height / maskCI.extent.height
        return maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    // MARK: - Strategy 3: Saliency-based Mask

    /// 使用注意力显著性检测生成 mask，比色彩泛洪更智能
    /// 能识别图片中"值得注意"的区域，适合商品/衣物图片
    private func generateSaliencyMask(for cgImage: CGImage, targetExtent: CGRect) throws -> CIImage {
        // 先尝试 objectness-based（适合独立物体）
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw RemovalError.noSubject
        }

        let saliencyMap = CIImage(cvPixelBuffer: observation.pixelBuffer)

        // Saliency map 分辨率较低，需要放大到原图尺寸
        let scaleX = targetExtent.width / saliencyMap.extent.width
        let scaleY = targetExtent.height / saliencyMap.extent.height
        let scaled = saliencyMap.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Saliency map 值较低（0~1 浮点），需要增强对比度使其成为可用的 mask
        // 使用 CIColorControls 增强对比度 + 亮度
        let enhanced = scaled
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 5.0,
                kCIInputBrightnessKey: 0.3
            ])
            .cropped(to: targetExtent)

        // 再做一次轻微模糊，平滑低分辨率放大后的像素化
        return enhanced.applyingGaussianBlur(sigma: 3.0).cropped(to: targetExtent)
    }

    // MARK: - Strategy 4: Safe White Background Removal

    /// 安全的白背景移除：只移除与边缘连通的近白色区域
    /// 有保护机制：如果要移除超过 65% 的像素，认为检测失败，抛出错误
    private func generateSafeColorMask(for cgImage: CGImage) throws -> CIImage {
        let width = cgImage.width
        let height = cgImage.height
        let bpp = 4
        let totalPixels = width * height
        var pixels = [UInt8](repeating: 0, count: totalPixels * bpp)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bpp,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RemovalError.processingFailed("无法创建位图上下文")
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 采样边缘颜色
        let bgColors = sampleBorderColors(pixels: pixels, width: width, height: height, bpp: bpp)

        // 使用更紧的阈值（35 而不是 55），减少误判
        let threshold: Double = 35.0

        var mask = [UInt8](repeating: 255, count: totalPixels)
        var visited = [Bool](repeating: false, count: totalPixels)
        var removedCount = 0

        // 边缘种子
        var queue: [(Int, Int)] = []
        queue.reserveCapacity(2 * (width + height))

        for x in 0..<width {
            queue.append((x, 0))
            queue.append((x, height - 1))
        }
        for y in 1..<(height - 1) {
            queue.append((0, y))
            queue.append((width - 1, y))
        }

        for (x, y) in queue {
            let idx = y * width + x
            guard !visited[idx] else { continue }
            visited[idx] = true
            if isSimilarToBackground(pixels: pixels, idx: idx, bpp: bpp, backgrounds: bgColors, threshold: threshold) {
                mask[idx] = 0
                removedCount += 1
            }
        }

        // BFS 泛洪，带实时安全检查
        var head = 0
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            let cidx = cy * width + cx
            guard mask[cidx] == 0 else { continue }

            for (nx, ny) in [(cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)] {
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nidx = ny * width + nx
                guard !visited[nidx] else { continue }
                visited[nidx] = true
                if isSimilarToBackground(pixels: pixels, idx: nidx, bpp: bpp, backgrounds: bgColors, threshold: threshold) {
                    mask[nidx] = 0
                    removedCount += 1
                    queue.append((nx, ny))

                    // 🛡️ 安全保护：如果已标记移除超过 65%，说明检测错误
                    if removedCount > Int(Double(totalPixels) * 0.65) {
                        throw RemovalError.processingFailed("背景区域过大（>\(Int(Double(removedCount) / Double(totalPixels) * 100))%），可能误判前景，中止处理")
                    }
                }
            }
        }

        // 🛡️ 额外安全检查：前景区域太小（< 10%）也说明有问题
        let foregroundCount = totalPixels - removedCount
        if foregroundCount < Int(Double(totalPixels) * 0.10) {
            throw RemovalError.processingFailed("前景区域过小（<10%），可能误判，中止处理")
        }

        // 边界柔化
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                guard mask[idx] == 255 else { continue }
                guard isNearBackground(mask: mask, x: x, y: y, width: width, height: height, radius: 2) else { continue }

                let offset = idx * bpp
                let r = Double(pixels[offset])
                let g = Double(pixels[offset + 1])
                let b = Double(pixels[offset + 2])

                var minDist = Double.greatestFiniteMagnitude
                for bg in bgColors {
                    let dist = sqrt(pow(r - bg.0, 2) + pow(g - bg.1, 2) + pow(b - bg.2, 2))
                    minDist = min(minDist, dist)
                }
                let alpha = min(1.0, max(0.0, (minDist - threshold * 0.7) / 20.0))
                mask[idx] = UInt8(alpha * 255)
            }
        }

        guard let maskCtx = CGContext(
            data: &mask,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let maskCG = maskCtx.makeImage() else {
            throw RemovalError.processingFailed("蒙版生成失败")
        }

        return CIImage(cgImage: maskCG)
    }

    // MARK: - Color Helpers

    private func isSimilarToBackground(pixels: [UInt8], idx: Int, bpp: Int, backgrounds: [(Double, Double, Double)], threshold: Double) -> Bool {
        let offset = idx * bpp
        let r = Double(pixels[offset])
        let g = Double(pixels[offset + 1])
        let b = Double(pixels[offset + 2])
        for bg in backgrounds {
            if sqrt(pow(r - bg.0, 2) + pow(g - bg.1, 2) + pow(b - bg.2, 2)) < threshold {
                return true
            }
        }
        return false
    }

    private func isNearBackground(mask: [UInt8], x: Int, y: Int, width: Int, height: Int, radius: Int) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < width, ny >= 0, ny < height, mask[ny * width + nx] == 0 {
                    return true
                }
            }
        }
        return false
    }

    private func sampleBorderColors(pixels: [UInt8], width: Int, height: Int, bpp: Int) -> [(Double, Double, Double)] {
        var samples: [(Double, Double, Double)] = []
        let step = max(1, min(width, height) / 50)

        for x in stride(from: 0, to: width, by: step) {
            for y in [0, height - 1] {
                let o = (y * width + x) * bpp
                samples.append((Double(pixels[o]), Double(pixels[o+1]), Double(pixels[o+2])))
            }
        }
        for y in stride(from: 0, to: height, by: step) {
            for x in [0, width - 1] {
                let o = (y * width + x) * bpp
                samples.append((Double(pixels[o]), Double(pixels[o+1]), Double(pixels[o+2])))
            }
        }

        guard !samples.isEmpty else { return [(255, 255, 255)] }
        return kMeans(samples, k: 3)
    }

    private func kMeans(_ samples: [(Double, Double, Double)], k: Int) -> [(Double, Double, Double)] {
        guard samples.count >= k else { return samples }
        let step = samples.count / k
        var centers = (0..<k).map { samples[$0 * step] }

        for _ in 0..<10 {
            var clusters = Array(repeating: [(Double, Double, Double)](), count: k)
            for s in samples {
                var best = 0
                var bestD = Double.greatestFiniteMagnitude
                for (i, c) in centers.enumerated() {
                    let d = pow(s.0-c.0, 2) + pow(s.1-c.1, 2) + pow(s.2-c.2, 2)
                    if d < bestD { bestD = d; best = i }
                }
                clusters[best].append(s)
            }
            for i in 0..<k {
                guard !clusters[i].isEmpty else { continue }
                let n = Double(clusters[i].count)
                centers[i] = (
                    clusters[i].reduce(0) { $0 + $1.0 } / n,
                    clusters[i].reduce(0) { $0 + $1.1 } / n,
                    clusters[i].reduce(0) { $0 + $1.2 } / n
                )
            }
        }
        return centers
    }

    // MARK: - Trim to Opaque Area

    private func trimToOpaqueArea(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        let bpp = 4
        var px = [UInt8](repeating: 0, count: w * h * bpp)

        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * bpp,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                if px[(y * w + x) * bpp + 3] > 10 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }

        guard minX < maxX, minY < maxY else { return image }

        let pad = max(Int(Double(min(w, h)) * 0.02), 4)
        let rect = CGRect(
            x: max(0, minX - pad),
            y: max(0, minY - pad),
            width: min(w - max(0, minX - pad), maxX - minX + 2 * pad),
            height: min(h - max(0, minY - pad), maxY - minY + 2 * pad)
        )

        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    // MARK: - Resize

    private func resizeIfNeeded(_ cgImage: CGImage, maxDimension: Int) -> CGImage {
        let w = cgImage.width, h = cgImage.height
        guard w > maxDimension || h > maxDimension else { return cgImage }

        let scale = CGFloat(maxDimension) / CGFloat(max(w, h))
        let nw = Int(CGFloat(w) * scale)
        let nh = Int(CGFloat(h) * scale)

        guard let ctx = CGContext(
            data: nil, width: nw, height: nh,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return cgImage }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? cgImage
    }
}
