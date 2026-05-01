import UIKit
import Vision
import os.log

/// 多信号衣物相似度检测服务
///
/// 检测流程：
/// 1. dHash 感知哈希 → 捕获完全相同的图片（重复导入）
/// 2. 品类过滤 → 仅比较同大类衣物（消除跨品类误判）
/// 3. HSV 颜色直方图 → 颜色差异大的跳过（不同色系的同款不告警）
/// 4. VNFeaturePrint → 在前三步筛选后比较款式纹理细节
actor SimilarityCheckService {
    static let shared = SimilarityCheckService()

    private let logger = Logger(subsystem: "SmartWardrobe", category: "SimilarityCheck")

    // MARK: - Thresholds

    /// dHash 汉明距离阈值：≤ 5 认为是同一张图片
    static let duplicateHashDistance = 5
    /// Bhattacharyya 颜色距离阈值：0=完全相同，1=完全不同，>0.30 跳过
    static let colorDistanceThreshold: Float = 0.30
    /// VNFeaturePrint 距离阈值（仅在同品类+同色系内使用）
    static let featurePrintThreshold: Float = 12.0

    // MARK: - Types

    enum SimilarityLevel: Comparable {
        case duplicate  // 重复导入（同一张图）
        case high       // 高度相似（同品类、颜色相近、款式相近）

        var label: String {
            switch self {
            case .duplicate: return "疑似重复导入"
            case .high: return "高度相似"
            }
        }

        var icon: String {
            switch self {
            case .duplicate: return "exclamationmark.triangle.fill"
            case .high: return "eye.trianglebadge.exclamationmark"
            }
        }
    }

    struct SimilarMatch: Identifiable {
        let id = UUID()
        let clothingItem: ClothingItem
        let score: Float            // 0–1 综合相似分
        let level: SimilarityLevel
        let thumbnail: UIImage?
    }

    struct CheckResult: Identifiable {
        let id = UUID()
        let matches: [SimilarMatch]

        var hasDuplicate: Bool { matches.contains { $0.level == .duplicate } }
        var isEmpty: Bool { matches.isEmpty }
    }

    // MARK: - Signatures（供保存时缓存）

    struct ImageSignatures {
        let hash: Int64
        let histogramData: Data
    }

    func computeSignatures(for image: UIImage) -> ImageSignatures {
        let hash = Int64(bitPattern: computeDHash(for: image))
        let histogram = computeHSVHistogram(for: image)
        return ImageSignatures(hash: hash, histogramData: encodeHistogram(histogram))
    }

    // MARK: - Public Check

    func check(
        image: UIImage,
        against existingItems: [ClothingItem],
        newItemCategory: Category? = nil,
        maxResults: Int = 5
    ) async -> CheckResult {

        let newHash = computeDHash(for: image)
        let newHistogram = computeHSVHistogram(for: image)
        let newFeaturePrint = computeFeaturePrint(for: image)

        // 计算新图的品类（取顶级）
        let newTopCategoryName: String?
        if let cat = newItemCategory {
            newTopCategoryName = (cat.parent ?? cat).name
        } else {
            newTopCategoryName = nil
        }

        var matches: [SimilarMatch] = []

        for item in existingItems {
            guard let thumbName = item.thumbnailFileName,
                  let thumbnail = ImageStorageService.shared.loadThumbnail(fileName: thumbName)
            else { continue }

            // ── Phase 1: dHash 重复检测（所有衣物都检查）──
            let itemHash = UInt64(bitPattern: item.imageHash ?? Int64(bitPattern: computeDHash(for: thumbnail)))
            let hammingDist = hammingDistance(newHash, itemHash)

            if hammingDist <= Self.duplicateHashDistance {
                matches.append(SimilarMatch(
                    clothingItem: item,
                    score: 1.0 - Float(hammingDist) / 64.0,
                    level: .duplicate,
                    thumbnail: thumbnail
                ))
                continue
            }

            // ── Phase 2: 品类过滤 ──
            guard let ntc = newTopCategoryName else { continue }
            let itemTopCategory = item.topCategory
            guard let itc = itemTopCategory?.name, ntc == itc else { continue }

            // ── Phase 3: 颜色直方图 ──
            let itemHistogram: [Float]
            if let data = item.colorHistogramData {
                itemHistogram = decodeHistogram(data)
            } else {
                itemHistogram = computeHSVHistogram(for: thumbnail)
            }
            let colorDist = bhattacharyyaDistance(newHistogram, itemHistogram)
            guard colorDist < Self.colorDistanceThreshold else { continue }

            // ── Phase 4: VNFeaturePrint 款式细节 ──
            guard let newFP = newFeaturePrint,
                  let itemFP = computeFeaturePrint(for: thumbnail)
            else { continue }

            var fpDistance: Float = 0
            do {
                try itemFP.computeDistance(&fpDistance, to: newFP)
            } catch {
                continue
            }
            guard fpDistance < Self.featurePrintThreshold else { continue }

            // ── 综合得分 ──
            let colorScore  = 1.0 - colorDist / Self.colorDistanceThreshold
            let fpScore     = 1.0 - fpDistance / Self.featurePrintThreshold
            let score       = 0.5 * colorScore + 0.5 * fpScore

            if score > 0.3 {
                matches.append(SimilarMatch(
                    clothingItem: item,
                    score: score,
                    level: .high,
                    thumbnail: thumbnail
                ))
            }
        }

        let sorted = matches.sorted { $0.score > $1.score }.prefix(maxResults)
        logger.info("相似度检查: 共比较 \(existingItems.count) 件，发现 \(sorted.count) 件相似")
        return CheckResult(matches: Array(sorted))
    }

    // MARK: - dHash（感知哈希）

    private func computeDHash(for image: UIImage) -> UInt64 {
        let w = 9, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let cgImage = image.cgImage,
              let ctx = CGContext(
                data: &pixels, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return 0 }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hash: UInt64 = 0
        for row in 0..<h {
            for col in 0..<(w - 1) {
                let left  = pixels[row * w + col]
                let right = pixels[row * w + col + 1]
                hash = (hash << 1) | (left > right ? 1 : 0)
            }
        }
        return hash
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - HSV 颜色直方图（108 bins: 12色相 × 3饱和度 × 3明度）

    private func computeHSVHistogram(for image: UIImage) -> [Float] {
        let binCount = 108
        guard let cgImage = image.cgImage,
              cgImage.width > 0, cgImage.height > 0 else {
            return [Float](repeating: 0, count: binCount)
        }

        let w = cgImage.width
        let h = cgImage.height
        var pixelData = [UInt8](repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: &pixelData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [Float](repeating: 0, count: binCount) }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var histogram = [Float](repeating: 0, count: binCount)
        var count: Float = 0

        // 均匀采样，最多取 10000 个像素
        let total = w * h
        let step = max(1, total / 10_000)

        for i in stride(from: 0, to: total, by: step) {
            let offset = i * 4
            let alpha = Float(pixelData[offset + 3]) / 255.0
            guard alpha > 0.3 else { continue }   // 跳过透明区域

            // premultiplied 反推原始颜色
            let r = min(1, Float(pixelData[offset])     / (255.0 * alpha))
            let g = min(1, Float(pixelData[offset + 1]) / (255.0 * alpha))
            let b = min(1, Float(pixelData[offset + 2]) / (255.0 * alpha))

            let (hue, sat, val) = rgbToHSV(r: r, g: g, b: b)
            let hBin = min(11, Int(hue / 30.0))
            let sBin = min(2,  Int(sat * 3.0))
            let vBin = min(2,  Int(val * 3.0))

            histogram[hBin * 9 + sBin * 3 + vBin] += 1
            count += 1
        }

        if count > 0 {
            for i in 0..<histogram.count { histogram[i] /= count }
        }
        return histogram
    }

    private func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        let v = maxV
        let s = maxV > 0.001 ? delta / maxV : 0

        var h: Float = 0
        if delta > 0.001 {
            if maxV == r      { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxV == g { h = 60 * ((b - r) / delta + 2) }
            else              { h = 60 * ((r - g) / delta + 4) }
            if h < 0 { h += 360 }
        }
        return (h, s, v)
    }

    /// Bhattacharyya 距离：0 = 完全相同，趋近 1 = 完全不同
    private func bhattacharyyaDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 1.0 }
        var bc: Float = 0
        for i in 0..<a.count { bc += sqrt(a[i] * b[i]) }
        return 1.0 - bc
    }

    private func encodeHistogram(_ histogram: [Float]) -> Data {
        histogram.withUnsafeBytes { Data($0) }
    }

    private func decodeHistogram(_ data: Data) -> [Float] {
        data.withUnsafeBytes { ptr -> [Float] in
            guard let base = ptr.baseAddress else { return [] }
            let count = data.count / MemoryLayout<Float>.size
            return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: Float.self), count: count))
        }
    }

    // MARK: - VNFeaturePrint

    private func computeFeaturePrint(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }
}
