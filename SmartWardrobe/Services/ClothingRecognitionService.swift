import UIKit
import SwiftData
import os.log

/// 衣物属性自动识别服务
///
/// 通过 LLM Vision API 分析衣物图片，自动识别分类、颜色、材质、领型、袖长等属性。
/// 识别失败时静默降级，不影响保存流程。
actor ClothingRecognitionService {
    static let shared = ClothingRecognitionService()

    private let logger = Logger(subsystem: "SmartWardrobe", category: "Recognition")

    // MARK: - Result

    struct RecognitionResult {
        var categoryName: String?       // 子分类名，如 "T恤"、"牛仔裤"
        var colorHexValues: [String]    // 匹配 PresetColors 的 hex
        var colorStyle: String?         // 纯色/条纹/格子/印花/拼接/渐变
        var material: String?
        var collarType: String?
        var sleeveLength: String?
        var closureType: String?
        var pantLength: String?
        var skirtLength: String?
        var heelHeight: String?
        var bagSize: String?
        var seasons: [String]
    }

    // MARK: - Public API

    /// 识别衣物属性（识别失败返回 nil，但颜色识别始终尝试）
    func recognize(image: UIImage) async -> RecognitionResult? {
        // 1. 本地颜色提取（不依赖网络，始终执行）
        let detectedColors = extractDominantColors(from: image, maxCount: 5)

        // 2. LLM 视觉识别（其他属性）
        guard let base64 = encodeImage(image) else {
            logger.warning("图片编码失败")
            return RecognitionResult(
                categoryName: nil,
                colorHexValues: detectedColors.map { $0.hex },
                colorStyle: nil,
                material: nil, collarType: nil, sleeveLength: nil, closureType: nil,
                pantLength: nil, skirtLength: nil, heelHeight: nil, bagSize: nil,
                seasons: []
            )
        }

        let systemPrompt = buildSystemPrompt()
        let messages: [LLMService.VisionMessage] = [
            LLMService.VisionMessage(role: "system", content: [
                .text(systemPrompt)
            ]),
            LLMService.VisionMessage(role: "user", content: [
                .text("请识别这张衣物图片的属性。"),
                .imageBase64(base64, detail: "low")
            ])
        ]

        do {
            let response = try await LLMService.shared.visionChat(
                messages: messages,
                temperature: 0.1,
                maxTokens: 1000
            )

            var result = parseResponse(response)

            // LLM 颜色优先（能理解光照/语义），本地算法兜底
            if result?.colorHexValues.isEmpty ?? true {
                result?.colorHexValues = detectedColors.map { $0.hex }
                logger.info("LLM 未返回颜色，使用本地识别")
            }

            logger.info("识别完成: 分类=\(result?.categoryName ?? "nil"), 颜色=\(result?.colorHexValues.count ?? 0)种")
            return result
        } catch {
            logger.warning("LLM识别失败: \(error.localizedDescription)，使用本地颜色")

            // LLM 失败时仍返回本地颜色
            return RecognitionResult(
                categoryName: nil,
                colorHexValues: detectedColors.map { $0.hex },
                colorStyle: nil,
                material: nil, collarType: nil, sleeveLength: nil, closureType: nil,
                pantLength: nil, skirtLength: nil, heelHeight: nil, bagSize: nil,
                seasons: []
            )
        }
    }

    /// 在 SwiftData 中查找匹配的 Category 对象
    /// 如果 LLM 返回的是大类名（如"上衣"），自动映射到该大类下的"其他xx"子分类
    @MainActor
    func findCategory(named name: String, in context: ModelContext) -> Category? {
        let descriptor = FetchDescriptor<Category>()
        guard let categories = try? context.fetch(descriptor) else { return nil }

        // 优先精确匹配子分类
        if let exact = categories.first(where: { $0.name == name && !$0.isTopLevel }) {
            return exact
        }

        // 如果匹配到的是大类名，兜底到该大类下的"其他xx"子分类
        let topLevelNames = ["上衣", "裤子", "半身裙", "连体装", "鞋", "包", "帽子", "首饰", "配饰"]
        if topLevelNames.contains(name) {
            let fallbackName = "其他\(name)"
            if let fallback = categories.first(where: { $0.name == fallbackName && !$0.isTopLevel }) {
                return fallback
            }
            // 如果"其他xx"子分类也不存在，返回大类本身
            return categories.first(where: { $0.name == name && $0.isTopLevel })
        }

        // 最后尝试匹配顶级分类
        return categories.first(where: { $0.name == name && $0.isTopLevel })
    }

    // MARK: - Image Encoding

    private func encodeImage(_ image: UIImage) -> String? {
        // 缩小到 512px 以控制 base64 大小
        let maxSize: CGFloat = 512
        let size = image.size
        let scale = min(maxSize / max(size.width, size.height), 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.6)?.base64EncodedString()
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        return """
        你是一个服装属性识别专家。根据图片识别衣物的各项属性。

        ## 分类体系（格式为大类: 子分类1, 子分类2, ...）
        - 上衣: T恤, POLO衫, 衬衫, 女衫, 马甲, 毛衣/针织, 卫衣, 西装, 牛仔衣, 棒球服, 夹克, 棉衣/羊羔绒, 风衣, 大衣, 羽绒服, 皮衣, 皮草, 其他上衣
        - 裤子: 牛仔裤, 休闲裤, 运动裤, 西裤, 短裤, 打底裤, 阔腿裤, 其他裤子
        - 半身裙: 短裙, 半身长裙, 百褶裙, A字裙, 包臀裙, 其他半身裙
        - 连体装: 连衣裙, 连体裤, 套装, 其他连体装
        - 鞋: 运动鞋, 帆布鞋, 高跟鞋, 平底鞋, 靴子, 凉鞋/拖鞋, 乐福鞋, 其他鞋
        - 包: 双肩包, 手提包, 斜挎包, 钱包, 腰包, 其他包
        - 帽子: 棒球帽, 渔夫帽, 针织帽, 贝雷帽, 其他帽子
        - 首饰: 项链, 耳环, 手链/手镯, 戒指, 胸针, 其他首饰
        - 配饰: 围巾, 腰带, 墨镜, 手套, 袜子, 其他配饰

        ## 可用属性值（必须严格从以下选项中选择，不能自创）
        - 颜色（从以下名称中选，按面积从大到小排列，最多5个）: \(AppConstants.PresetColors.all.map(\.name).joined(separator: ", "))
        - 色系: \(AppConstants.ColorStyle.all.joined(separator: ", "))
        - 材质: \(AppConstants.Material.all.joined(separator: ", "))
        - 领型（仅上衣/连体装）: \(AppConstants.CollarType.all.joined(separator: ", "))
        - 袖长（仅上衣/连体装）: \(AppConstants.SleeveLength.all.joined(separator: ", "))
        - 闭合方式（上衣/裤子/半身裙/连体装）: \(AppConstants.ClosureType.all.joined(separator: ", "))
        - 闭合方式（鞋）: \(AppConstants.ShoeClosureType.all.joined(separator: ", "))
        - 闭合方式（包）: \(AppConstants.ClosureType.all.joined(separator: ", "))
        - 裤长（仅裤子）: \(AppConstants.PantLength.all.joined(separator: ", "))
        - 裙长（仅半身裙/连体装）: \(AppConstants.SkirtLength.all.joined(separator: ", "))
        - 跟高（仅鞋）: \(AppConstants.HeelHeight.all.joined(separator: ", "))
        - 包型（仅包）: \(AppConstants.BagSize.all.joined(separator: ", "))
        - 季节: 春, 夏, 秋, 冬

        ## 返回格式（严格 JSON）
        ```json
        {
          "category": "子分类名",
          "colors": ["黑色"],
          "colorStyle": "纯色",
          "material": "棉",
          "collarType": "圆领",
          "sleeveLength": "短袖",
          "closureType": "套头",
          "pantLength": null,
          "skirtLength": null,
          "heelHeight": null,
          "bagSize": null,
          "seasons": ["春", "夏"]
        }
        ```

        ## 规则
        1. category 必须是上面列出的子分类名之一
        2. 如果衣物不属于任何具体子分类，使用对应大类下的"其他"选项（如"其他上衣"、"其他裤子"）；请不要直接输出大类，如"上衣"、"裤子"等
        3. 只返回与该分类相关的属性，不相关的填 null
        4. 如果某个属性无法从图片判断，填 null
        5. seasons 根据衣物厚度/材质推断适合的季节，最多选择两个适合季节
        6. colors 填写衣物本身的颜色（忽略光照/阴影造成的色偏），按面积从大到小排列
        7. 只输出 JSON，不要其他文字
        """
    }

    // MARK: - Parse Response

    private func parseResponse(_ response: String) -> RecognitionResult? {
        // 提取 JSON（可能被 markdown 包裹）
        let jsonString: String
        if let range = response.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            jsonString = String(response[range])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.warning("JSON 解析失败: \(response.prefix(200))")
            return nil
        }

        // 验证并提取属性值
        let validColorStyles = Set(AppConstants.ColorStyle.all)
        let validMaterials = Set(AppConstants.Material.all)
        let validCollarTypes = Set(AppConstants.CollarType.all)
        let validSleeveLengths = Set(AppConstants.SleeveLength.all)
        let validClosureTypes = Set(AppConstants.ClosureType.all + AppConstants.ShoeClosureType.all)
        let validPantLengths = Set(AppConstants.PantLength.all)
        let validSkirtLengths = Set(AppConstants.SkirtLength.all)
        let validHeelHeights = Set(AppConstants.HeelHeight.all)
        let validBagSizes = Set(AppConstants.BagSize.all)
        let validSeasons = Set(AppConstants.Seasons.all)

        return RecognitionResult(
            categoryName: json["category"] as? String,
            colorHexValues: mapColorNames(json["colors"] as? [String] ?? []),
            colorStyle: validate(json["colorStyle"] as? String, in: validColorStyles),
            material: validate(json["material"] as? String, in: validMaterials),
            collarType: validate(json["collarType"] as? String, in: validCollarTypes),
            sleeveLength: validate(json["sleeveLength"] as? String, in: validSleeveLengths),
            closureType: validate(json["closureType"] as? String, in: validClosureTypes),
            pantLength: validate(json["pantLength"] as? String, in: validPantLengths),
            skirtLength: validate(json["skirtLength"] as? String, in: validSkirtLengths),
            heelHeight: validate(json["heelHeight"] as? String, in: validHeelHeights),
            bagSize: validate(json["bagSize"] as? String, in: validBagSizes),
            seasons: (json["seasons"] as? [String] ?? []).filter { validSeasons.contains($0) }
        )
    }

    private func validate(_ value: String?, in validSet: Set<String>) -> String? {
        guard let v = value, validSet.contains(v) else { return nil }
        return v
    }

    private func mapColorNames(_ names: [String]) -> [String] {
        let presets = AppConstants.PresetColors.all
        return names.compactMap { name in
            presets.first { $0.name == name }?.hex
        }
    }

    /// 仅提取颜色（不调用 LLM），用于图片编辑后重新分析
    func extractColors(from image: UIImage) -> [String] {
        extractDominantColors(from: image, maxCount: 5).map { $0.hex }
    }

    struct ColorDetectionResult {
        let name: String
        let hex: String
        let ratio: Float
    }

    /// 返回颜色名称 + hex + 占比，供测试和调试使用
    func extractColorsDetailed(from image: UIImage) -> [ColorDetectionResult] {
        extractDominantColors(from: image).map {
            ColorDetectionResult(name: $0.name, hex: $0.hex, ratio: $0.ratio)
        }
    }

    // MARK: - 本地主色提取（CIELAB + K-means）

    private struct DetectedColor {
        let name: String
        let hex: String
        let ratio: Float
    }

    /// Lab 颜色：人眼感知均匀的色彩空间
    private struct LabColor {
        let L: Float, a: Float, b: Float

        /// 色度（chroma），越大颜色越鲜艳
        var chroma: Float { sqrtf(a * a + b * b) }

        func distance(to other: LabColor) -> Float {
            let dL = L - other.L, da = a - other.a, db = b - other.b
            return dL * dL + da * da + db * db
        }

        /// 降低亮度权重的距离，让不同光照下的同色相聚到一起
        func chromaWeightedDistance(to other: LabColor) -> Float {
            let dL = L - other.L, da = a - other.a, db = b - other.b
            return 0.3 * dL * dL + da * da + db * db
        }
    }

    /// 从前景像素中提取主色：
    /// 1. 采样不透明像素 → 转 Lab 色彩空间
    /// 2. K-means 聚类找到 k 个真实主色簇
    /// 3. 每个簇质心匹配最近的 PresetColor
    private func extractDominantColors(from image: UIImage, maxCount: Int = 5) -> [DetectedColor] {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { return [] }

        let w = cgImage.width, h = cgImage.height
        var pixelData = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixelData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 1. 采样前景像素 → Lab
        let total = w * h
        let step = max(1, total / 10000)
        var samples: [LabColor] = []
        samples.reserveCapacity(10000)

        for i in stride(from: 0, to: total, by: step) {
            let off = i * 4
            let alpha = Float(pixelData[off + 3]) / 255.0
            guard alpha > 0.8 else { continue }
            let r = min(1.0, Float(pixelData[off]) / (255.0 * alpha))
            let g = min(1.0, Float(pixelData[off + 1]) / (255.0 * alpha))
            let b = min(1.0, Float(pixelData[off + 2]) / (255.0 * alpha))
            let lab = rgbToLab(r, g, b)
            // 仅过滤真正的图像伪影，保留黑色和白色衣物像素
            if lab.L < 3 && lab.chroma < 3 { continue }
            if lab.L > 99 && lab.chroma < 2 { continue }
            samples.append(lab)
        }
        guard samples.count >= 10 else { return [] }

        // 2. K-means 聚类（k=8，Farthest-First 初始化，迭代 12 次）
        let k = min(8, samples.count)
        var centers = farthestFirstInit(samples: samples, k: k)
        var assignments = [Int](repeating: 0, count: samples.count)

        for _ in 0..<12 {
            // Assign（用色度加权距离，降低亮度差异的影响）
            for (i, s) in samples.enumerated() {
                var best = 0, bestD: Float = .greatestFiniteMagnitude
                for (j, c) in centers.enumerated() {
                    let d = s.chromaWeightedDistance(to: c)
                    if d < bestD { bestD = d; best = j }
                }
                assignments[i] = best
            }
            // Update centers
            for j in 0..<k {
                var sumL: Float = 0, sumA: Float = 0, sumB: Float = 0, cnt: Float = 0
                for (i, s) in samples.enumerated() where assignments[i] == j {
                    sumL += s.L; sumA += s.a; sumB += s.b; cnt += 1
                }
                if cnt > 0 {
                    centers[j] = LabColor(L: sumL / cnt, a: sumA / cnt, b: sumB / cnt)
                }
            }
        }

        // 3. 统计每簇大小
        var clusterSizes = [Int](repeating: 0, count: k)
        for a in assignments { clusterSizes[a] += 1 }
        let totalSamples = Float(samples.count)

        struct ClusterInfo {
            var center: LabColor
            var ratio: Float
        }
        var clusters = (0..<k).map {
            ClusterInfo(center: centers[$0], ratio: Float(clusterSizes[$0]) / totalSamples)
        }
        .filter { $0.ratio > 0.03 }
        .sorted { $0.ratio > $1.ratio }

        // 4. 合并感知相似的簇（色相角区分阴影 vs 拼接色）
        var merged = [ClusterInfo]()
        for cluster in clusters {
            if let idx = merged.firstIndex(where: { existing in
                let dL = existing.center.L - cluster.center.L
                let dA = existing.center.a - cluster.center.a
                let dB = existing.center.b - cluster.center.b
                let dAB2 = dA * dA + dB * dB
                let dL2 = dL * dL

                let bothAchromatic = existing.center.chroma < 10 && cluster.center.chroma < 10
                if bothAchromatic {
                    return dL2 < 225
                }

                let bothChromatic = existing.center.chroma >= 10 && cluster.center.chroma >= 10
                if bothChromatic {
                    let h1 = atan2f(existing.center.b, existing.center.a)
                    let h2 = atan2f(cluster.center.b, cluster.center.a)
                    var dH = abs(h1 - h2)
                    if dH > .pi { dH = 2 * .pi - dH }
                    if dH < 0.26 {
                        return dL2 + dAB2 < 2500
                    }
                }

                return dAB2 < 250 && dL2 < 625
            }) {
                // 加权合并：保留更大簇的色相，累加比例
                let total = merged[idx].ratio + cluster.ratio
                let w1 = merged[idx].ratio / total, w2 = cluster.ratio / total
                merged[idx] = ClusterInfo(
                    center: LabColor(
                        L: merged[idx].center.L * w1 + cluster.center.L * w2,
                        a: merged[idx].center.a * w1 + cluster.center.a * w2,
                        b: merged[idx].center.b * w1 + cluster.center.b * w2
                    ),
                    ratio: total
                )
            } else {
                merged.append(cluster)
            }
        }
        clusters = merged.sorted { $0.ratio > $1.ratio }

        // 4. 每簇质心匹配最近 PresetColor（Lab 距离）
        let presets = AppConstants.PresetColors.all
        let presetLabs = presets.map { p -> LabColor in
            let (r, g, b) = hexToRGB(p.hex)
            return rgbToLab(r, g, b)
        }

        var results: [DetectedColor] = []
        var usedPresets = Set<Int>()

        for cluster in clusters {
            var bestIdx = 0, bestDist: Float = .greatestFiniteMagnitude
            for (i, pLab) in presetLabs.enumerated() {
                guard !usedPresets.contains(i) else { continue }
                let d = cluster.center.distance(to: pLab)
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            usedPresets.insert(bestIdx)
            results.append(DetectedColor(
                name: presets[bestIdx].name,
                hex: presets[bestIdx].hex,
                ratio: cluster.ratio
            ))
            if results.count >= maxCount { break }
        }

        // 过滤噪声：保留占比 > 5% 或 > 主色 12% 的颜色
        if results.count > 1 {
            let maxRatio = results.first?.ratio ?? 1.0
            results = results.filter { $0.ratio > 0.05 || $0.ratio > maxRatio * 0.12 }
        }

        return results
    }

    /// Farthest-First Traversal 初始化：确保初始簇心均匀分布
    private func farthestFirstInit(samples: [LabColor], k: Int) -> [LabColor] {
        guard !samples.isEmpty else { return [] }
        var centers: [LabColor] = [samples[samples.count / 2]]
        var minDists = [Float](repeating: .greatestFiniteMagnitude, count: samples.count)

        for _ in 1..<k {
            let lastCenter = centers.last!
            var bestIdx = 0, bestDist: Float = 0
            for (i, s) in samples.enumerated() {
                let d = s.chromaWeightedDistance(to: lastCenter)
                if d < minDists[i] { minDists[i] = d }
                if minDists[i] > bestDist { bestDist = minDists[i]; bestIdx = i }
            }
            centers.append(samples[bestIdx])
        }
        return centers
    }

    // MARK: - Color Space Conversion

    private func hexToRGB(_ hex: String) -> (Float, Float, Float) {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt32(h, radix: 16) else { return (0, 0, 0) }
        return (Float((val >> 16) & 0xFF) / 255.0,
                Float((val >> 8) & 0xFF) / 255.0,
                Float(val & 0xFF) / 255.0)
    }

    /// sRGB → CIELAB（D65 白点）
    private func rgbToLab(_ r: Float, _ g: Float, _ b: Float) -> LabColor {
        // sRGB → 线性 RGB
        func linearize(_ v: Float) -> Float {
            v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
        }
        let lr = linearize(r), lg = linearize(g), lb = linearize(b)

        // 线性 RGB → XYZ（sRGB D65 矩阵）
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047
        let y = (0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb) / 1.00000
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883

        // XYZ → Lab
        func f(_ t: Float) -> Float {
            t > 0.008856 ? cbrtf(t) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return LabColor(L: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz))
    }
}
