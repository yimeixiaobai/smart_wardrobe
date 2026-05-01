import Testing
import UIKit
@testable import SmartWardrobe

@Suite("颜色识别准确性")
struct ColorDetectionTests {

    // MARK: - Helpers

    /// 用水平色带合成测试图片（每个 band 等宽，最后一条补齐余数行）
    private func makeBandedImage(
        width: Int = 200, height: Int = 200,
        bands: [(r: UInt8, g: UInt8, b: UInt8)]
    ) -> UIImage {
        let count = max(bands.count, 1)
        let bandH = height / count
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (i, band) in bands.enumerated() {
            let yStart = i * bandH
            let yEnd = (i == count - 1) ? height : yStart + bandH
            for y in yStart..<yEnd {
                for x in 0..<width {
                    let off = (y * width + x) * 4
                    pixels[off]     = band.r
                    pixels[off + 1] = band.g
                    pixels[off + 2] = band.b
                    pixels[off + 3] = 255
                }
            }
        }
        return pixels.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress!, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return UIImage(cgImage: ctx.makeImage()!)
        }
    }

    private func detect(_ image: UIImage) async -> [ClothingRecognitionService.ColorDetectionResult] {
        await ClothingRecognitionService.shared.extractColorsDetailed(from: image)
    }

    private func log(_ label: String, _ r: [ClothingRecognitionService.ColorDetectionResult]) {
        let detail = r.map { "\($0.name)(#\($0.hex), \(Int($0.ratio * 100))%)" }
            .joined(separator: "  ")
        print("🎨 [\(label)] \(r.count)色 → \(detail)")
    }

    // MARK: - 1) 纯色

    @Test("纯黑色 → 黑色")
    func solidBlack() async {
        let r = await detect(makeBandedImage(bands: [(26, 26, 26)]))
        log("纯黑", r)
        #expect(r.contains { $0.hex == "1A1A1A" }, "应识别出黑色")
    }

    @Test("纯白色 → 白色")
    func solidWhite() async {
        let r = await detect(makeBandedImage(bands: [(248, 248, 248)]))
        log("纯白", r)
        #expect(r.contains { $0.hex == "F8F8F8" }, "应识别出白色")
    }

    @Test("纯红色 → 红色")
    func solidRed() async {
        let r = await detect(makeBandedImage(bands: [(204, 41, 54)]))
        log("纯红", r)
        #expect(r.contains { $0.hex == "CC2936" }, "应识别出红色")
    }

    @Test("纯蓝色 → 蓝色")
    func solidBlue() async {
        let r = await detect(makeBandedImage(bands: [(47, 84, 150)]))
        log("纯蓝", r)
        #expect(r.contains { $0.hex == "2F5496" }, "应识别出蓝色")
    }

    // MARK: - 2) 双色拼接

    @Test("红 + 蓝 50/50 → 应识别两种")
    func redBlue() async {
        let r = await detect(makeBandedImage(bands: [(204, 41, 54), (47, 84, 150)]))
        log("红蓝", r)
        #expect(r.contains { $0.hex == "CC2936" }, "应含红色")
        #expect(r.contains { $0.hex == "2F5496" }, "应含蓝色")
    }

    @Test("黑 + 白 50/50 → 应识别两种")
    func blackWhite() async {
        let r = await detect(makeBandedImage(bands: [(26, 26, 26), (248, 248, 248)]))
        log("黑白", r)
        #expect(r.contains { $0.hex == "1A1A1A" }, "应含黑色")
        #expect(r.contains { $0.hex == "F8F8F8" }, "应含白色")
    }

    @Test("藏蓝 + 浅蓝 50/50 → 同色相不同亮度不应合并")
    func navyLightBlue() async {
        let r = await detect(makeBandedImage(bands: [(30, 48, 80), (126, 180, 210)]))
        log("深浅蓝", r)
        #expect(r.count >= 2, "深蓝和浅蓝应被识别为不同颜色")
    }

    @Test("深灰 + 浅灰 50/50 → 不应合并")
    func darkLightGray() async {
        let r = await detect(makeBandedImage(bands: [(64, 64, 64), (184, 184, 184)]))
        log("深浅灰", r)
        #expect(r.count >= 2, "深灰和浅灰应被识别为不同颜色")
    }

    // MARK: - 3) 三色拼接

    @Test("红 + 白 + 蓝 等分 → 应识别三种")
    func threeColorEqual() async {
        let r = await detect(makeBandedImage(bands: [
            (204, 41, 54), (248, 248, 248), (47, 84, 150)
        ]))
        log("红白蓝", r)
        #expect(r.count >= 3, "三种明显不同的颜色应全部识别")
    }

    @Test("70% 黑 + 20% 白 + 10% 红 → 至少识别2种")
    func threeColorUneven() async {
        let r = await detect(makeBandedImage(bands: [
            (26, 26, 26), (26, 26, 26), (26, 26, 26), (26, 26, 26),
            (26, 26, 26), (26, 26, 26), (26, 26, 26),
            (248, 248, 248), (248, 248, 248),
            (204, 41, 54)
        ]))
        log("7:2:1", r)
        #expect(r.contains { $0.hex == "1A1A1A" }, "应含黑色")
        #expect(r.count >= 2, "白色或红色至少一个应被识别")
    }

    // MARK: - 4) 五色拼接

    @Test("五色等分 → 应识别至少4种")
    func fiveColors() async {
        let r = await detect(makeBandedImage(bands: [
            (204, 41, 54),   // 红
            (47, 84, 150),   // 蓝
            (58, 125, 92),   // 绿
            (212, 167, 48),  // 黄
            (26, 26, 26)     // 黑
        ]))
        log("五色", r)
        #expect(r.count >= 4, "五种颜色应至少识别4种")
    }

    // MARK: - 5) 边界情况

    @Test("纯色只返回1种颜色")
    func solidReturnsSingle() async {
        let r = await detect(makeBandedImage(bands: [(128, 128, 128)]))
        log("纯灰", r)
        #expect(r.count == 1, "纯色图应只返回1种颜色，实际 \(r.count) 种")
    }

    @Test("非常接近的两种红不应产生重复预设")
    func nearRedShades() async {
        let r = await detect(makeBandedImage(bands: [(200, 40, 50), (210, 45, 55)]))
        log("近似红", r)
        let uniqueHex = Set(r.map(\.hex))
        #expect(uniqueHex.count == r.count, "不应出现重复的预设颜色")
    }

    // MARK: - 6) 阴影场景

    @Test("纯红带阴影 → 应识别为1种颜色")
    func redWithShadow() async {
        let r = await detect(makeBandedImage(bands: [
            (204, 41, 54), (204, 41, 54), (204, 41, 54), (204, 41, 54),
            (204, 41, 54), (204, 41, 54), (204, 41, 54),
            (140, 28, 37), (140, 28, 37), (140, 28, 37)
        ]))
        log("红带阴影", r)
        #expect(r.count == 1, "纯色带阴影不应识别为两种颜色，实际 \(r.count) 种")
    }

    @Test("纯蓝带高光 → 应识别为1种颜色")
    func blueWithHighlight() async {
        let r = await detect(makeBandedImage(bands: [
            (47, 84, 150), (47, 84, 150), (47, 84, 150), (47, 84, 150),
            (47, 84, 150), (47, 84, 150), (47, 84, 150),
            (90, 130, 190), (90, 130, 190), (90, 130, 190)
        ]))
        log("蓝带高光", r)
        #expect(r.count == 1, "纯色带高光不应识别为两种颜色，实际 \(r.count) 种")
    }

    @Test("纯绿带深阴影 → 应识别为1种颜色")
    func greenWithDeepShadow() async {
        let r = await detect(makeBandedImage(bands: [
            (58, 125, 92), (58, 125, 92), (58, 125, 92), (58, 125, 92),
            (58, 125, 92), (58, 125, 92),
            (30, 65, 48), (30, 65, 48), (30, 65, 48), (30, 65, 48)
        ]))
        log("绿带深影", r)
        #expect(r.count == 1, "纯色带深阴影不应识别为两种颜色，实际 \(r.count) 种")
    }

    @Test("阴影修复不影响拼接色：藏蓝+浅蓝仍为2色")
    func patchworkStillWorks() async {
        let r = await detect(makeBandedImage(bands: [(30, 48, 80), (126, 180, 210)]))
        log("拼接验证", r)
        #expect(r.count >= 2, "藏蓝+浅蓝拼接不应被合并")
    }

}
