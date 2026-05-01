import UIKit
import os.log

// Thread safety: NSCache is internally thread-safe; file names use UUIDs so
// concurrent writes never target the same path. Sendable conformance is safe.
final class ImageStorageService: @unchecked Sendable {
    private let logger = Logger(subsystem: "SmartWardrobe", category: "ImageStorage")
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default
    private let thumbnailSize: CGFloat = 300
    private let ioQueue = DispatchQueue(label: "com.smartwardrobe.imageio", qos: .userInitiated)

    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        cache.totalCostLimit = 150 * 1024 * 1024 // 150MB
        return cache
    }()

    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        return cache
    }()

    private var imagesDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ClothingImages", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var thumbnailsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    struct SaveResult {
        let imageFileName: String
        let originalFileName: String
        let thumbnailFileName: String
    }

    func saveImages(processed: UIImage, original: UIImage) async throws -> SaveResult {
        let id = UUID().uuidString

        let processedName = "\(id)_processed.png"
        let originalName = "\(id)_original.jpg"
        let thumbnailName = "\(id)_thumb.png"

        let pngData = processed.pngData()
        let jpegData = original.jpegData(compressionQuality: 0.8)
        let thumbnail = generateThumbnail(from: processed)
        let thumbData = thumbnail.pngData()

        let imgDir = imagesDirectory
        let thumbDir = thumbnailsDirectory

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async {
                do {
                    if let pngData {
                        try pngData.write(to: imgDir.appendingPathComponent(processedName))
                    }
                    if let jpegData {
                        try jpegData.write(to: imgDir.appendingPathComponent(originalName))
                    }
                    if let thumbData {
                        try thumbData.write(to: thumbDir.appendingPathComponent(thumbnailName))
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return SaveResult(
            imageFileName: processedName,
            originalFileName: originalName,
            thumbnailFileName: thumbnailName
        )
    }

    func loadImage(fileName: String) -> UIImage? {
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let url = imagesDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func loadThumbnail(fileName: String) -> UIImage? {
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = thumbnailsDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        thumbnailCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func deleteImages(imageFileName: String?, originalFileName: String?, thumbnailFileName: String?) {
        if let name = imageFileName {
            imageCache.removeObject(forKey: name as NSString)
            let url = imagesDirectory.appendingPathComponent(name)
            do { try fileManager.removeItem(at: url) } catch {
                logger.warning("Failed to delete image \(name): \(error.localizedDescription)")
            }
        }
        if let name = originalFileName {
            imageCache.removeObject(forKey: name as NSString)
            let url = imagesDirectory.appendingPathComponent(name)
            do { try fileManager.removeItem(at: url) } catch {
                logger.warning("Failed to delete original \(name): \(error.localizedDescription)")
            }
        }
        if let name = thumbnailFileName {
            thumbnailCache.removeObject(forKey: name as NSString)
            let url = thumbnailsDirectory.appendingPathComponent(name)
            do { try fileManager.removeItem(at: url) } catch {
                logger.warning("Failed to delete thumbnail \(name): \(error.localizedDescription)")
            }
        }
    }

    func invalidateCache(for fileName: String) {
        imageCache.removeObject(forKey: fileName as NSString)
        thumbnailCache.removeObject(forKey: fileName as NSString)
    }

    struct CanvasSlotInfo {
        let position: CGPoint
        let scale: CGFloat
        let rotation: CGFloat // degrees
        let zIndex: Int
        let thumbnailFileName: String?
        let imageFileName: String?
    }

    func generateOutfitThumbnail(slots: [CanvasSlotInfo], bgColor: UIColor) -> String? {
        let canvasSize = CGSize(width: 400, height: 600)
        let sorted = slots.sorted { $0.zIndex < $1.zIndex }

        let slotImages: [(CanvasSlotInfo, UIImage)] = sorted.compactMap { slot in
            // 优先加载全尺寸图以保持原始宽高比
            let image: UIImage?
            if let imgName = slot.imageFileName {
                image = loadImage(fileName: imgName)
            } else if let thumbName = slot.thumbnailFileName {
                image = loadThumbnail(fileName: thumbName)
            } else {
                image = nil
            }
            guard let img = image else { return nil }
            return (slot, img)
        }

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for (slot, uiImage) in slotImages {
                let frameW = 120 * slot.scale
                let frameH = 120 * slot.scale
                let imgAR = uiImage.size.width / uiImage.size.height
                let fitW: CGFloat, fitH: CGFloat
                if imgAR > 1 {
                    fitW = frameW
                    fitH = frameW / imgAR
                } else {
                    fitH = frameH
                    fitW = frameH * imgAR
                }
                let drawRect = CGRect(
                    x: -fitW / 2,
                    y: -fitH / 2,
                    width: fitW, height: fitH
                )
                let cgCtx = ctx.cgContext
                cgCtx.saveGState()
                cgCtx.translateBy(x: slot.position.x, y: slot.position.y)
                cgCtx.rotate(by: slot.rotation * .pi / 180)
                uiImage.draw(in: drawRect)
                cgCtx.restoreGState()
            }
        }

        let thumbnail = image.resized(to: 300)
        let fileName = "\(UUID().uuidString)_outfit_thumb.jpg"
        let dir = thumbnailsDirectory
        let url = dir.appendingPathComponent(fileName)
        if let data = thumbnail.jpegData(compressionQuality: 0.7) {
            do {
                try data.write(to: url)
                return fileName
            } catch {
                try? fileManager.removeItem(at: url)
                logger.warning("Failed to write outfit thumbnail: \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func generateThumbnail(from image: UIImage) -> UIImage {
        let maxSize = thumbnailSize
        let size = image.size
        let scale: CGFloat

        if size.width > size.height {
            scale = maxSize / size.width
        } else {
            scale = maxSize / size.height
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
