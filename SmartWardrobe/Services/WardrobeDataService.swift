import Foundation
import SwiftData
import ZIPFoundation
import os.log

actor WardrobeDataService {
    static let shared = WardrobeDataService()
    private let logger = Logger(subsystem: "SmartWardrobe", category: "DataService")

    // MARK: - Export

    func exportData(context: ModelContext) throws -> URL {
        let manifest = try buildManifest(context: context)
        let jsonData = try JSONEncoder.iso8601Encoder.encode(manifest)

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("SmartWardrobe_Export_\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        try jsonData.write(to: tmpDir.appendingPathComponent("manifest.json"))

        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDirSrc = docs.appendingPathComponent("ClothingImages")
        let thumbsDirSrc = docs.appendingPathComponent("Thumbnails")

        if fm.fileExists(atPath: imagesDirSrc.path) {
            try fm.copyItem(at: imagesDirSrc, to: tmpDir.appendingPathComponent("ClothingImages"))
        }
        if fm.fileExists(atPath: thumbsDirSrc.path) {
            try fm.copyItem(at: thumbsDirSrc, to: tmpDir.appendingPathComponent("Thumbnails"))
        }

        let zipURL = fm.temporaryDirectory.appendingPathComponent("智能衣橱备份_\(Self.dateStamp()).zip")
        try? fm.removeItem(at: zipURL)
        try fm.zipItem(at: tmpDir, to: zipURL)

        return zipURL
    }

    // MARK: - Import

    func importData(from zipURL: URL, context: ModelContext) throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("SmartWardrobe_Import_\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        try fm.unzipItem(at: zipURL, to: tmpDir)

        var manifestURL = tmpDir.appendingPathComponent("manifest.json")
        if !fm.fileExists(atPath: manifestURL.path) {
            if let nested = try fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
                .first(where: { $0.hasDirectoryPath }),
               fm.fileExists(atPath: nested.appendingPathComponent("manifest.json").path) {
                manifestURL = nested.appendingPathComponent("manifest.json")
            } else {
                throw DataError.invalidArchive
            }
        }

        let jsonData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.iso8601Decoder.decode(ExportData.self, from: jsonData)

        guard manifest.version <= 1 else {
            throw DataError.unsupportedVersion(manifest.version)
        }

        let manifestParent = manifestURL.deletingLastPathComponent()

        deleteAllData(context: context)
        try restoreImages(from: manifestParent)
        restoreModels(from: manifest, context: context)

        try context.save()
        logger.info("Import complete: \(manifest.clothingItems.count) items, \(manifest.outfits.count) outfits")
    }

    // MARK: - Build Manifest

    private func buildManifest(context: ModelContext) throws -> ExportData {
        let categories = try context.fetch(FetchDescriptor<Category>())
        let items = try context.fetch(FetchDescriptor<ClothingItem>())
        let outfits = try context.fetch(FetchDescriptor<Outfit>())
        let slots = try context.fetch(FetchDescriptor<OutfitSlot>())
        let records = try context.fetch(FetchDescriptor<WearRecord>())
        let recordItems = try context.fetch(FetchDescriptor<WearRecordItem>())

        return ExportData(
            version: 1,
            exportDate: Date(),
            categories: categories.map { c in
                ExportCategory(
                    id: c.id, name: c.name, icon: c.icon,
                    sortOrder: c.sortOrder, isSystem: c.isSystem,
                    createdAt: c.createdAt, parentId: c.parent?.id
                )
            },
            clothingItems: items.map { i in
                ExportClothingItem(
                    id: i.id, name: i.name, categoryId: i.category?.id,
                    colorHexValues: i.colorHexValues, colorStyle: i.colorStyle,
                    storageLocation: i.storageLocation, status: i.status,
                    seasons: i.seasons, purchasePrice: i.purchasePrice,
                    purchaseDate: i.purchaseDate, purchaseLink: i.purchaseLink,
                    material: i.material, size: i.size, collarType: i.collarType,
                    sleeveLength: i.sleeveLength, closureType: i.closureType,
                    washingMethod: i.washingMethod, pantLength: i.pantLength,
                    skirtLength: i.skirtLength, heelHeight: i.heelHeight,
                    bagSize: i.bagSize, brand: i.brand, tags: i.tags,
                    notes: i.notes, isFavorite: i.isFavorite,
                    wearCount: i.wearCount, imageFileName: i.imageFileName,
                    originalImageFileName: i.originalImageFileName,
                    thumbnailFileName: i.thumbnailFileName,
                    createdAt: i.createdAt, updatedAt: i.updatedAt
                )
            },
            outfits: outfits.map { o in
                ExportOutfit(
                    id: o.id, name: o.name, occasion: o.occasion,
                    notes: o.notes, backgroundStyle: o.backgroundStyle,
                    seasons: o.seasons, thumbnailFileName: o.thumbnailFileName,
                    createdAt: o.createdAt
                )
            },
            outfitSlots: slots.map { s in
                ExportOutfitSlot(
                    id: s.id, outfitId: s.outfit?.id,
                    clothingItemId: s.clothingItem?.id,
                    positionX: s.positionX, positionY: s.positionY,
                    scale: s.scale, rotation: s.rotation, zIndex: s.zIndex
                )
            },
            wearRecords: records.map { r in
                ExportWearRecord(
                    id: r.id, date: r.date, note: r.note,
                    mood: r.mood, occasion: r.occasion,
                    outfitId: r.outfit?.id, createdAt: r.createdAt
                )
            },
            wearRecordItems: recordItems.map { ri in
                ExportWearRecordItem(
                    id: ri.id,
                    wearRecordId: ri.wearRecord?.id,
                    clothingItemId: ri.clothingItem?.id
                )
            }
        )
    }

    // MARK: - Delete All

    private func deleteAllData(context: ModelContext) {
        try? context.delete(model: WearRecordItem.self)
        try? context.delete(model: WearRecord.self)
        try? context.delete(model: OutfitSlot.self)
        try? context.delete(model: Outfit.self)
        try? context.delete(model: ClothingItem.self)
        try? context.delete(model: Category.self)

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.removeItem(at: docs.appendingPathComponent("ClothingImages"))
        try? fm.removeItem(at: docs.appendingPathComponent("Thumbnails"))
    }

    // MARK: - Restore Images

    private func restoreImages(from sourceDir: URL) throws {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let srcImages = sourceDir.appendingPathComponent("ClothingImages")
        let srcThumbs = sourceDir.appendingPathComponent("Thumbnails")
        let dstImages = docs.appendingPathComponent("ClothingImages")
        let dstThumbs = docs.appendingPathComponent("Thumbnails")

        if fm.fileExists(atPath: srcImages.path) {
            try fm.createDirectory(at: dstImages, withIntermediateDirectories: true)
            for file in (try? fm.contentsOfDirectory(at: srcImages, includingPropertiesForKeys: nil)) ?? [] {
                let dest = dstImages.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: file, to: dest)
            }
        }
        if fm.fileExists(atPath: srcThumbs.path) {
            try fm.createDirectory(at: dstThumbs, withIntermediateDirectories: true)
            for file in (try? fm.contentsOfDirectory(at: srcThumbs, includingPropertiesForKeys: nil)) ?? [] {
                let dest = dstThumbs.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: file, to: dest)
            }
        }
    }

    // MARK: - Restore Models

    private func restoreModels(from data: ExportData, context: ModelContext) {
        var categoryMap: [UUID: Category] = [:]
        for ec in data.categories {
            let cat = Category(name: ec.name, icon: ec.icon, sortOrder: ec.sortOrder, isSystem: ec.isSystem)
            cat.id = ec.id
            cat.createdAt = ec.createdAt
            context.insert(cat)
            categoryMap[ec.id] = cat
        }
        for ec in data.categories {
            if let parentId = ec.parentId, let parent = categoryMap[parentId] {
                categoryMap[ec.id]?.parent = parent
            }
        }

        var itemMap: [UUID: ClothingItem] = [:]
        for ei in data.clothingItems {
            let item = ClothingItem()
            item.id = ei.id
            item.name = ei.name
            item.category = ei.categoryId.flatMap { categoryMap[$0] }
            item.colorHexValues = ei.colorHexValues
            item.colorStyle = ei.colorStyle
            item.storageLocation = ei.storageLocation
            item.status = ei.status
            item.seasons = ei.seasons
            item.purchasePrice = ei.purchasePrice
            item.purchaseDate = ei.purchaseDate
            item.purchaseLink = ei.purchaseLink
            item.material = ei.material
            item.size = ei.size
            item.collarType = ei.collarType
            item.sleeveLength = ei.sleeveLength
            item.closureType = ei.closureType
            item.washingMethod = ei.washingMethod
            item.pantLength = ei.pantLength
            item.skirtLength = ei.skirtLength
            item.heelHeight = ei.heelHeight
            item.bagSize = ei.bagSize
            item.brand = ei.brand
            item.tags = ei.tags
            item.notes = ei.notes
            item.isFavorite = ei.isFavorite
            item.wearCount = ei.wearCount
            item.imageFileName = ei.imageFileName
            item.originalImageFileName = ei.originalImageFileName
            item.thumbnailFileName = ei.thumbnailFileName
            item.createdAt = ei.createdAt
            item.updatedAt = ei.updatedAt
            context.insert(item)
            itemMap[ei.id] = item
        }

        var outfitMap: [UUID: Outfit] = [:]
        for eo in data.outfits {
            let outfit = Outfit(name: eo.name)
            outfit.id = eo.id
            outfit.occasion = eo.occasion
            outfit.notes = eo.notes
            outfit.backgroundStyle = eo.backgroundStyle
            outfit.seasons = eo.seasons
            outfit.thumbnailFileName = eo.thumbnailFileName
            outfit.createdAt = eo.createdAt
            context.insert(outfit)
            outfitMap[eo.id] = outfit
        }

        for es in data.outfitSlots {
            let slot = OutfitSlot()
            slot.id = es.id
            slot.outfit = es.outfitId.flatMap { outfitMap[$0] }
            slot.clothingItem = es.clothingItemId.flatMap { itemMap[$0] }
            slot.positionX = es.positionX
            slot.positionY = es.positionY
            slot.scale = es.scale
            slot.rotation = es.rotation
            slot.zIndex = es.zIndex
            context.insert(slot)
        }

        var recordMap: [UUID: WearRecord] = [:]
        for er in data.wearRecords {
            let record = WearRecord(date: er.date)
            record.id = er.id
            record.note = er.note
            record.mood = er.mood
            record.occasion = er.occasion
            record.outfit = er.outfitId.flatMap { outfitMap[$0] }
            record.createdAt = er.createdAt
            context.insert(record)
            recordMap[er.id] = record
        }

        for eri in data.wearRecordItems {
            let ri = WearRecordItem(clothingItem: eri.clothingItemId.flatMap { itemMap[$0] })
            ri.id = eri.id
            ri.wearRecord = eri.wearRecordId.flatMap { recordMap[$0] }
            context.insert(ri)
        }
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    // MARK: - Errors

    enum DataError: LocalizedError {
        case invalidArchive
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "不是有效的衣橱备份文件"
            case .unsupportedVersion(let v):
                return "备份版本（v\(v)）过高，请更新 App 后重试"
            }
        }
    }
}

// MARK: - Codable Structs

struct ExportData: Codable {
    let version: Int
    let exportDate: Date
    let categories: [ExportCategory]
    let clothingItems: [ExportClothingItem]
    let outfits: [ExportOutfit]
    let outfitSlots: [ExportOutfitSlot]
    let wearRecords: [ExportWearRecord]
    let wearRecordItems: [ExportWearRecordItem]
}

struct ExportCategory: Codable {
    let id: UUID
    let name: String
    let icon: String
    let sortOrder: Int
    let isSystem: Bool
    let createdAt: Date
    let parentId: UUID?
}

struct ExportClothingItem: Codable {
    let id: UUID
    let name: String
    let categoryId: UUID?
    let colorHexValues: [String]
    let colorStyle: String?
    let storageLocation: String?
    let status: String
    let seasons: [String]
    let purchasePrice: Double?
    let purchaseDate: Date?
    let purchaseLink: String?
    let material: String?
    let size: String?
    let collarType: String?
    let sleeveLength: String?
    let closureType: String?
    let washingMethod: String?
    let pantLength: String?
    let skirtLength: String?
    let heelHeight: String?
    let bagSize: String?
    let brand: String?
    let tags: [String]
    let notes: String?
    let isFavorite: Bool
    let wearCount: Int
    let imageFileName: String?
    let originalImageFileName: String?
    let thumbnailFileName: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ExportOutfit: Codable {
    let id: UUID
    let name: String
    let occasion: String?
    let notes: String?
    let backgroundStyle: String
    let seasons: [String]
    let thumbnailFileName: String?
    let createdAt: Date
}

struct ExportOutfitSlot: Codable {
    let id: UUID
    let outfitId: UUID?
    let clothingItemId: UUID?
    let positionX: Double
    let positionY: Double
    let scale: Double
    let rotation: Double
    let zIndex: Int
}

struct ExportWearRecord: Codable {
    let id: UUID
    let date: Date
    let note: String?
    let mood: String?
    let occasion: String?
    let outfitId: UUID?
    let createdAt: Date
}

struct ExportWearRecordItem: Codable {
    let id: UUID
    let wearRecordId: UUID?
    let clothingItemId: UUID?
}

// MARK: - JSON Encoder/Decoder with ISO 8601

extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
