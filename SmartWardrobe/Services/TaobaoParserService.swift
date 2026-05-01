import UIKit
import Vision

final class TaobaoParserService {
    static let shared = TaobaoParserService()

    struct ProductInfo {
        var title: String?
        var price: Double?
        var imageURL: URL?
        /// 页面中发现的所有候选商品图（用于多图选择）
        var imageURLs: [URL] = []
        var image: UIImage?
        var sourceURL: URL?
    }

    // MARK: - 淘口令解析

    /// 从文本中提取淘宝/天猫链接
    func extractURL(from text: String) -> URL? {
        // 1. 匹配 tb.cn 短链接 (m.tb.cn, e.tb.cn, s.tb.cn 等各种子域名)
        let shortLinkPattern = "https?://[a-zA-Z0-9]*\\.?tb\\.cn/[^\\s\"'>，。！？「」【】]+"
        if let match = text.range(of: shortLinkPattern, options: .regularExpression) {
            return URL(string: String(text[match]))
        }

        // 2. 匹配淘宝/天猫商品直链
        let directPattern = "https?://(?:item\\.taobao|detail\\.tmall|h5\\.m\\.taobao)\\.com/[^\\s\"'>，。！？「」【】]+"
        if let match = text.range(of: directPattern, options: .regularExpression) {
            return URL(string: String(text[match]))
        }

        // 3. 兜底：匹配文本中任意含 taobao/tmall/tb.cn 的链接
        let anyURLPattern = "https?://[^\\s\"'>，。！？「」【】]+"
        if let match = text.range(of: anyURLPattern, options: .regularExpression) {
            let urlStr = String(text[match])
            if urlStr.contains("taobao") || urlStr.contains("tmall") || urlStr.contains("tb.cn") {
                return URL(string: urlStr)
            }
        }

        return nil
    }

    /// 从淘口令文本中提取商品名称（「...」 之间的内容）
    func extractTitle(from text: String) -> String? {
        let pattern = "「([^」]+)」"
        if let match = text.range(of: pattern, options: .regularExpression) {
            var title = String(text[match])
            title = title.replacingOccurrences(of: "「", with: "").replacingOccurrences(of: "」", with: "")
            return title.isEmpty ? nil : title
        }
        return nil
    }

    /// 注入到 WebView 的 JS，用于提取商品信息
    var extractionJS: String {
        """
        (function() {
            var result = { title: null, price: null, imageURL: null };

            // --- 提取标题 ---
            // 优先 og:title
            var ogTitle = document.querySelector('meta[property="og:title"]');
            if (ogTitle) result.title = ogTitle.getAttribute('content');
            // 回退到 document.title
            if (!result.title) result.title = document.title;
            // 清理淘宝后缀
            if (result.title) {
                result.title = result.title.replace(/-淘宝网$/, '').replace(/-天猫.*$/, '').replace(/-tmall\\.com$/, '').trim();
            }

            // --- 提取价格 ---
            // 淘宝/天猫的价格常见 class 名
            var priceSelectors = [
                '.tm-price',
                '.tm-promo-price .tm-price',
                '#J_PromoPriceNum',
                '#J_StrPrice .tb-rmb-num',
                '.Price--currentPrice--.*',
                '[class*="Price--currentPrice"]',
                '[class*="price"]'
            ];
            for (var i = 0; i < priceSelectors.length; i++) {
                try {
                    var el = document.querySelector(priceSelectors[i]);
                    if (el) {
                        var priceText = el.textContent.replace(/[^0-9.]/g, '');
                        if (priceText && parseFloat(priceText) > 0) {
                            result.price = priceText;
                            break;
                        }
                    }
                } catch(e) {}
            }
            // 兜底：正则搜索页面中的价格
            if (!result.price) {
                var body = document.body ? document.body.innerText : '';
                var priceMatch = body.match(/[¥￥]\\s*(\\d+\\.?\\d{0,2})/);
                if (priceMatch) result.price = priceMatch[1];
            }

            // --- 提取主图 ---
            // og:image
            var ogImage = document.querySelector('meta[property="og:image"]');
            if (ogImage) {
                var imgUrl = ogImage.getAttribute('content');
                if (imgUrl && !imgUrl.startsWith('http')) imgUrl = 'https:' + imgUrl;
                result.imageURL = imgUrl;
            }
            // 回退到商品主图
            if (!result.imageURL) {
                var imgSelectors = [
                    '#J_ImgBooth',
                    '.tb-main-pic img',
                    '[class*="MainPic"] img',
                    '.PicGallery--mainPic--* img',
                    '[class*="mainPic"] img',
                    '.main-image img'
                ];
                for (var j = 0; j < imgSelectors.length; j++) {
                    try {
                        var img = document.querySelector(imgSelectors[j]);
                        if (img) {
                            var src = img.getAttribute('src') || img.getAttribute('data-src');
                            if (src) {
                                if (!src.startsWith('http')) src = 'https:' + src;
                                result.imageURL = src;
                                break;
                            }
                        }
                    } catch(e) {}
                }
            }
            // 最终兜底：页面中最大的图片
            if (!result.imageURL) {
                var allImgs = document.querySelectorAll('img');
                var maxArea = 0;
                var maxSrc = null;
                allImgs.forEach(function(img) {
                    var area = (img.naturalWidth || img.width || 0) * (img.naturalHeight || img.height || 0);
                    var src = img.getAttribute('src') || img.getAttribute('data-src');
                    if (area > maxArea && src && !src.includes('icon') && !src.includes('logo') && !src.includes('avatar')) {
                        maxArea = area;
                        maxSrc = src;
                    }
                });
                if (maxSrc) {
                    if (!maxSrc.startsWith('http')) maxSrc = 'https:' + maxSrc;
                    result.imageURL = maxSrc;
                }
            }

            return JSON.stringify(result);
        })();
        """
    }

    // MARK: - 截图 OCR 识别

    struct OCRResult {
        var productName: String?
        var price: Double?
        var allTexts: [String]
    }

    /// 从截图中识别文字，提取商品名和价格
    func recognizeText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            return OCRResult(allTexts: [])
        }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let safeResume: (Result<OCRResult, Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    safeResume(.failure(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    safeResume(.success(OCRResult(allTexts: [])))
                    return
                }

                var allTexts: [String] = []
                var prices: [Double] = []
                var longestText: String?
                var maxLen = 0

                for observation in observations {
                    guard let text = observation.topCandidates(1).first?.string else { continue }
                    allTexts.append(text)

                    let pricePattern = "[¥￥]\\s*(\\d+\\.?\\d{0,2})"
                    if let match = text.range(of: pricePattern, options: .regularExpression) {
                        let num = String(text[match])
                            .replacingOccurrences(of: "¥", with: "")
                            .replacingOccurrences(of: "￥", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if let val = Double(num), val > 1 && val < 100000 {
                            prices.append(val)
                        }
                    }

                    let chineseCount = text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
                    if chineseCount > maxLen && text.count >= 4 {
                        maxLen = chineseCount
                        longestText = text
                    }
                }

                let result = OCRResult(
                    productName: longestText,
                    price: prices.first,
                    allTexts: allTexts
                )
                safeResume(.success(result))
            }

            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(error))
            }
        }
    }

    /// 检测截图中的主要商品图片区域
    func detectProductRegion(from image: UIImage) async throws -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let safeResume: (Result<CGRect?, Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                if let error {
                    safeResume(.failure(error))
                    return
                }

                guard let result = request.results?.first as? VNSaliencyImageObservation,
                      let salientObjects = result.salientObjects,
                      let biggest = salientObjects.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
                    safeResume(.success(nil))
                    return
                }

                let box = biggest.boundingBox
                let rect = CGRect(
                    x: box.origin.x,
                    y: 1 - box.origin.y - box.height,
                    width: box.width,
                    height: box.height
                )
                safeResume(.success(rect))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(error))
            }
        }
    }

    /// 裁剪图片
    func cropImage(_ image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: normalizedRect.origin.x * width,
            y: normalizedRect.origin.y * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
