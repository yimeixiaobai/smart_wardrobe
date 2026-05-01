import UIKit
import Vision
import os.log

actor MannequinPhotoService {
    static let shared = MannequinPhotoService()

    private let logger = Logger(subsystem: "SmartWardrobe", category: "MannequinPhoto")
    private let fileManager = FileManager.default

    // MARK: - Types

    struct BodyKeypoints: Codable {
        /// All points stored in top-left origin, normalized 0..1
        let nose: CGPoint?
        let neck: CGPoint?
        let rightShoulder: CGPoint?
        let leftShoulder: CGPoint?
        let rightElbow: CGPoint?
        let leftElbow: CGPoint?
        let rightWrist: CGPoint?
        let leftWrist: CGPoint?
        let rightHip: CGPoint?
        let leftHip: CGPoint?
        let rightKnee: CGPoint?
        let leftKnee: CGPoint?
        let rightAnkle: CGPoint?
        let leftAnkle: CGPoint?
        let root: CGPoint?

        var shoulderCenter: CGPoint? {
            guard let l = leftShoulder, let r = rightShoulder else { return nil }
            return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        }

        var hipCenter: CGPoint? {
            guard let l = leftHip, let r = rightHip else { return root }
            return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        }

        var kneeCenter: CGPoint? {
            guard let l = leftKnee, let r = rightKnee else { return nil }
            return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        }

        var ankleCenter: CGPoint? {
            guard let l = leftAnkle, let r = rightAnkle else { return nil }
            return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        }

        var shoulderWidth: CGFloat? {
            guard let l = leftShoulder, let r = rightShoulder else { return nil }
            return abs(l.x - r.x)
        }

        var hipWidth: CGFloat? {
            guard let l = leftHip, let r = rightHip else { return nil }
            return abs(l.x - r.x)
        }
    }

    struct PlacementGuide {
        let position: CGPoint   // normalized 0..1
        let scale: CGFloat
        let zIndex: Int
    }

    enum MannequinError: LocalizedError {
        case noBodyDetected
        case imageConversionFailed
        case lowConfidence

        var errorDescription: String? {
            switch self {
            case .noBodyDetected: return "未检测到人体，请使用全身正面照片"
            case .imageConversionFailed: return "图片处理失败"
            case .lowConfidence: return "关键点检测置信度过低，请尝试更清晰的全身照"
            }
        }
    }

    // MARK: - Storage

    private var mannequinDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("MannequinPhoto", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var photoURL: URL {
        mannequinDirectory.appendingPathComponent("mannequin_ref.jpg")
    }

    private var keypointsURL: URL {
        mannequinDirectory.appendingPathComponent("keypoints_cache.json")
    }

    private var cachedKeypoints: BodyKeypoints?

    // MARK: - Public API

    func saveReferencePhoto(_ image: UIImage) async throws -> BodyKeypoints {
        let oriented = image.fixedOrientation()
        guard let cgImage = oriented.cgImage else {
            throw MannequinError.imageConversionFailed
        }

        // Resize for processing
        let resized = resizeIfNeeded(cgImage, maxDimension: 2048)

        // Detect body pose
        let keypoints = try detectBodyPose(in: resized)

        // Save photo
        let uiImage = UIImage(cgImage: resized)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
            try jpegData.write(to: photoURL)
        }

        // Cache keypoints
        let encoder = JSONEncoder()
        let data = try encoder.encode(keypoints)
        try data.write(to: keypointsURL)
        cachedKeypoints = keypoints

        logger.info("模特照片已保存，成功检测到身体关键点")
        return keypoints
    }

    func loadReferencePhoto() -> UIImage? {
        guard fileManager.fileExists(atPath: photoURL.path),
              let data = try? Data(contentsOf: photoURL) else { return nil }
        return UIImage(data: data)
    }

    func hasReferencePhoto() -> Bool {
        fileManager.fileExists(atPath: photoURL.path)
    }

    func loadKeypoints() -> BodyKeypoints? {
        if let cached = cachedKeypoints { return cached }
        guard fileManager.fileExists(atPath: keypointsURL.path),
              let data = try? Data(contentsOf: keypointsURL),
              let kp = try? JSONDecoder().decode(BodyKeypoints.self, from: data) else { return nil }
        cachedKeypoints = kp
        return kp
    }

    func deleteReferencePhoto() {
        try? fileManager.removeItem(at: photoURL)
        try? fileManager.removeItem(at: keypointsURL)
        cachedKeypoints = nil
        logger.info("模特照片已删除")
    }

    // MARK: - Body Pose Detection

    private func detectBodyPose(in cgImage: CGImage) throws -> BodyKeypoints {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw MannequinError.noBodyDetected
        }

        func point(for joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? observation.recognizedPoint(joint),
                  p.confidence > 0.1 else { return nil }
            // Vision: bottom-left origin → flip Y for top-left
            return CGPoint(x: p.location.x, y: 1.0 - p.location.y)
        }

        let keypoints = BodyKeypoints(
            nose: point(for: .nose),
            neck: point(for: .neck),
            rightShoulder: point(for: .rightShoulder),
            leftShoulder: point(for: .leftShoulder),
            rightElbow: point(for: .rightElbow),
            leftElbow: point(for: .leftElbow),
            rightWrist: point(for: .rightWrist),
            leftWrist: point(for: .leftWrist),
            rightHip: point(for: .rightHip),
            leftHip: point(for: .leftHip),
            rightKnee: point(for: .rightKnee),
            leftKnee: point(for: .leftKnee),
            rightAnkle: point(for: .rightAnkle),
            leftAnkle: point(for: .leftAnkle),
            root: point(for: .root)
        )

        // 至少需要检测到躯干关键点
        guard keypoints.shoulderCenter != nil || keypoints.hipCenter != nil else {
            throw MannequinError.lowConfidence
        }

        return keypoints
    }

    // MARK: - Clothing Image Analysis

    /// 衣物图片的锚点信息，用于精确对位
    struct ClothingAnchors {
        let aspectRatio: CGFloat     // 图片宽/高
        let anchorNormY: CGFloat     // 主锚点 Y（0=顶, 1=底），对于上衣=肩线，裤子=腰线
        let widthAtAnchor: CGFloat   // 锚点处的宽度占图片宽度的比例 (0-1)
    }

    /// 分析衣物图片，提取关键锚点
    /// - 上衣：找上部 40% 最宽行 = 肩线
    /// - 裤子/裙：找上部 25% 最宽行 = 腰线
    /// - 其他：取图片中心
    nonisolated static func analyzeClothing(image: UIImage, categoryName: String) -> ClothingAnchors {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return ClothingAnchors(aspectRatio: 1, anchorNormY: 0.5, widthAtAnchor: 1.0)
        }

        let ar = size.width / size.height

        // 缩小到固定高度进行像素扫描
        let aH = 80
        let aW = max(1, Int(CGFloat(aH) * ar))
        guard let cgImage = image.cgImage else {
            return ClothingAnchors(aspectRatio: ar, anchorNormY: 0.15, widthAtAnchor: 0.8)
        }

        let bpp = 4
        var pixels = [UInt8](repeating: 0, count: aW * aH * bpp)
        guard let ctx = CGContext(
            data: &pixels, width: aW, height: aH,
            bitsPerComponent: 8, bytesPerRow: aW * bpp,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ClothingAnchors(aspectRatio: ar, anchorNormY: 0.15, widthAtAnchor: 0.8)
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: aW, height: aH))

        // 扫描每行：找最左和最右不透明像素
        struct RowInfo {
            let y: Int
            let left: Int
            let right: Int
            var width: Int { right - left + 1 }
        }

        var rows: [RowInfo] = []
        for y in 0..<aH {
            var left = aW, right = -1
            for x in 0..<aW {
                let alpha = pixels[(y * aW + x) * bpp + 3]
                if alpha > 30 {
                    left = min(left, x)
                    right = max(right, x)
                }
            }
            if right >= left {
                rows.append(RowInfo(y: y, left: left, right: right))
            }
        }

        guard !rows.isEmpty else {
            return ClothingAnchors(aspectRatio: ar, anchorNormY: 0.15, widthAtAnchor: 0.8)
        }

        // 根据分类在不同区间找最宽行作为锚点
        let searchFraction: Double
        switch categoryName {
        case "上衣", "连体装": searchFraction = 0.40
        case "裤子", "半身裙": searchFraction = 0.25
        case "帽子": searchFraction = 1.0  // 整体
        case "鞋": searchFraction = 1.0
        default: searchFraction = 0.5
        }

        guard let firstRow = rows.first else {
            return ClothingAnchors(aspectRatio: ar, anchorNormY: 0.15, widthAtAnchor: 0.8)
        }
        let firstOpaqueY = firstRow.y
        let searchLimit = firstOpaqueY + Int(Double(aH) * searchFraction)
        let topRows = rows.filter { $0.y <= searchLimit }
        let anchorRow = (topRows.max(by: { $0.width < $1.width })) ?? firstRow

        return ClothingAnchors(
            aspectRatio: ar,
            anchorNormY: CGFloat(anchorRow.y) / CGFloat(aH),
            widthAtAnchor: CGFloat(anchorRow.width) / CGFloat(aW)
        )
    }

    // MARK: - Placement Guide (clothing-aware)

    nonisolated static func placementGuide(
        for categoryName: String,
        subcategory: String = "",
        keypoints: BodyKeypoints,
        canvasSize: CGSize,
        clothingAnchors: ClothingAnchors? = nil
    ) -> PlacementGuide {
        let sw = keypoints.shoulderWidth ?? 0.22
        let hw = keypoints.hipWidth ?? 0.18

        guard let ca = clothingAnchors else {
            return fallbackPlacement(categoryName: categoryName, subcategory: subcategory,
                                     keypoints: keypoints, canvasSize: canvasSize)
        }

        switch categoryName {
        case "上衣":
            let anchor = keypoints.shoulderCenter ?? CGPoint(x: 0.5, y: 0.22)
            let bot = keypoints.hipCenter ?? CGPoint(x: 0.5, y: 0.50)
            let targetW = sw * 1.15 * canvasSize.width
            let targetH = abs(bot.y - anchor.y) * canvasSize.height * 1.1
            let s = computeScale(ca: ca, targetW: targetW, targetH: targetH)
            let pos = computePosition(ca: ca, bodyAnchor: anchor, scale: s, canvasSize: canvasSize)
            return PlacementGuide(position: pos, scale: s, zIndex: 3)

        case "裤子":
            let anchor = keypoints.hipCenter ?? CGPoint(x: 0.5, y: 0.50)
            let bot = keypoints.ankleCenter ?? CGPoint(x: 0.5, y: 0.88)
            let targetW = hw * 1.1 * canvasSize.width
            let targetH = abs(bot.y - anchor.y) * canvasSize.height * 1.05
            let s = computeScale(ca: ca, targetW: targetW, targetH: targetH)
            let pos = computePosition(ca: ca, bodyAnchor: anchor, scale: s, canvasSize: canvasSize)
            return PlacementGuide(position: pos, scale: s, zIndex: 2)

        case "半身裙":
            let anchor = keypoints.hipCenter ?? CGPoint(x: 0.5, y: 0.50)
            let bot = keypoints.kneeCenter ?? keypoints.ankleCenter ?? CGPoint(x: 0.5, y: 0.75)
            let targetW = hw * 1.3 * canvasSize.width
            let targetH = abs(bot.y - anchor.y) * canvasSize.height * 1.1
            let s = computeScale(ca: ca, targetW: targetW, targetH: targetH)
            let pos = computePosition(ca: ca, bodyAnchor: anchor, scale: s, canvasSize: canvasSize)
            return PlacementGuide(position: pos, scale: s, zIndex: 2)

        case "连体装":
            let anchor = keypoints.shoulderCenter ?? CGPoint(x: 0.5, y: 0.22)
            let bot = keypoints.ankleCenter ?? CGPoint(x: 0.5, y: 0.88)
            let targetW = sw * 1.15 * canvasSize.width
            let targetH = abs(bot.y - anchor.y) * canvasSize.height * 1.05
            let s = computeScale(ca: ca, targetW: targetW, targetH: targetH)
            let pos = computePosition(ca: ca, bodyAnchor: anchor, scale: s, canvasSize: canvasSize)
            return PlacementGuide(position: pos, scale: s, zIndex: 2)

        default:
            return fallbackPlacement(categoryName: categoryName, subcategory: subcategory,
                                     keypoints: keypoints, canvasSize: canvasSize)
        }
    }

    // MARK: - Scale & Position Helpers

    /// 计算缩放：优先填满目标区域，限制另一维度不超标
    ///
    /// scaledToFit 在 base*s 正方形帧中的渲染尺寸：
    ///   高图 (ar<1): width = base*s*ar,  height = base*s
    ///   宽图 (ar≥1): width = base*s,     height = base*s/ar
    private nonisolated static func computeScale(
        ca: ClothingAnchors, targetW: CGFloat, targetH: CGFloat, base: CGFloat = 120
    ) -> CGFloat {
        let ar = ca.aspectRatio
        let widthFactor: CGFloat = ar < 1 ? ar : 1.0
        let heightFactor: CGFloat = ar < 1 ? 1.0 : (1.0 / ar)

        let sFromW = targetW / (base * widthFactor * max(0.3, ca.widthAtAnchor))
        let sFromH = targetH / (base * heightFactor)

        // 取较大值让衣物填满身体区域，但另一维度不超过目标的 1.5 倍
        let generous = max(sFromW, sFromH)
        let cap = 1.5 * min(sFromW, sFromH)
        return clampScale(min(generous, cap))
    }

    /// 计算位置：衣物锚点行精确对齐身体关键点
    private nonisolated static func computePosition(
        ca: ClothingAnchors, bodyAnchor: CGPoint, scale: CGFloat,
        canvasSize: CGSize, base: CGFloat = 120
    ) -> CGPoint {
        let ar = ca.aspectRatio
        let rH: CGFloat = ar < 1 ? base * scale : base * scale / ar
        // 锚点行相对于帧中心的偏移
        let anchorOffset = (ca.anchorNormY - 0.5) * rH
        let centerY = bodyAnchor.y * canvasSize.height - anchorOffset
        return CGPoint(x: bodyAnchor.x, y: centerY / canvasSize.height)
    }

    // MARK: - Fallback (center-based, for accessories)

    private nonisolated static func fallbackPlacement(
        categoryName: String, subcategory: String,
        keypoints: BodyKeypoints, canvasSize: CGSize
    ) -> PlacementGuide {
        let base: CGFloat = 120
        let sw = keypoints.shoulderWidth ?? 0.22
        let hw = keypoints.hipWidth ?? 0.18

        switch categoryName {
        case "帽子":
            let pos = keypoints.nose.map {
                CGPoint(x: $0.x, y: $0.y - 0.08)
            } ?? CGPoint(x: 0.5, y: 0.06)
            return PlacementGuide(position: pos, scale: clampScale(sw * canvasSize.width * 0.7 / base), zIndex: 5)
        case "鞋":
            let pos = keypoints.ankleCenter.map {
                CGPoint(x: $0.x, y: $0.y + 0.04)
            } ?? CGPoint(x: 0.5, y: 0.92)
            return PlacementGuide(position: pos, scale: clampScale(sw * canvasSize.width * 0.5 / base), zIndex: 1)
        case "包":
            let pos = keypoints.rightHip.map {
                CGPoint(x: $0.x + 0.12, y: $0.y)
            } ?? CGPoint(x: 0.75, y: 0.50)
            return PlacementGuide(position: pos, scale: clampScale(hw * canvasSize.width * 0.8 / base), zIndex: 4)
        case "首饰":
            let pos: CGPoint
            switch subcategory {
            case "耳环": pos = keypoints.nose.map { CGPoint(x: $0.x + 0.06, y: $0.y) } ?? CGPoint(x: 0.56, y: 0.12)
            case "手链/手镯", "戒指": pos = keypoints.leftWrist ?? CGPoint(x: 0.3, y: 0.55)
            default: pos = keypoints.neck ?? CGPoint(x: 0.5, y: 0.20)
            }
            return PlacementGuide(position: pos, scale: 0.4, zIndex: 6)
        case "配饰":
            let pos: CGPoint
            let s: CGFloat
            switch subcategory {
            case "围巾": pos = keypoints.neck ?? CGPoint(x: 0.5, y: 0.20); s = 0.7
            case "腰带": pos = keypoints.hipCenter ?? CGPoint(x: 0.5, y: 0.50); s = 0.6
            case "墨镜": pos = keypoints.nose ?? CGPoint(x: 0.5, y: 0.10); s = 0.4
            case "手套": pos = keypoints.leftWrist ?? CGPoint(x: 0.3, y: 0.55); s = 0.5
            case "袜子": pos = keypoints.ankleCenter ?? CGPoint(x: 0.5, y: 0.85); s = 0.4
            default: pos = CGPoint(x: 0.5, y: 0.45); s = 0.6
            }
            return PlacementGuide(position: pos, scale: s, zIndex: 6)
        default:
            return PlacementGuide(position: CGPoint(x: 0.5, y: 0.45), scale: 1.0, zIndex: 3)
        }
    }

    // MARK: - Helpers

    private nonisolated static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private nonisolated static func clampScale(_ s: CGFloat) -> CGFloat {
        max(0.4, min(2.5, s))
    }

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
