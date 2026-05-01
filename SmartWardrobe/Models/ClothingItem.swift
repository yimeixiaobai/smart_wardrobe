import Foundation
import SwiftData

@Model
final class ClothingItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: Category?

    var colorHexValues: [String] = []
    var colorStyle: String?
    var storageLocation: String?
    var status: String = ClothingStatus.active.rawValue
    var seasons: [String] = []

    // Purchase info
    var purchasePrice: Double?
    var purchaseDate: Date?
    var purchaseLink: String?

    // Detail attributes
    var material: String?
    var size: String?
    var collarType: String?
    var sleeveLength: String?
    var closureType: String?
    var washingMethod: String?
    var pantLength: String?     // 裤长（裤子专属）
    var skirtLength: String?    // 裙长（半身裙/连体装专属）
    var heelHeight: String?     // 跟高（鞋专属）
    var bagSize: String?        // 包型（包专属）
    var brand: String?
    var tags: [String] = []
    var notes: String?

    var isFavorite: Bool = false
    var wearCount: Int = 0

    var imageFileName: String?
    var originalImageFileName: String?
    var thumbnailFileName: String?

    // 相似度检测缓存
    var imageHash: Int64?           // dHash 指纹，用于重复导入检测
    var colorHistogramData: Data?   // 108-bin HSV 直方图，用于颜色相似度

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \OutfitSlot.clothingItem)
    var outfitSlots: [OutfitSlot] = []

    @Relationship(deleteRule: .nullify, inverse: \WearRecordItem.clothingItem)
    var wearRecordItems: [WearRecordItem] = []

    init(name: String = "", category: Category? = nil) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 删除前清理孤立关系：移除 OutfitSlot / WearRecordItem，并删除变空的 Outfit
    func cleanupBeforeDelete(in context: ModelContext) {
        var affectedOutfits = Set<UUID>()
        for slot in outfitSlots {
            if let outfit = slot.outfit {
                affectedOutfits.insert(outfit.id)
            }
            context.delete(slot)
        }
        for recordItem in wearRecordItems {
            if let record = recordItem.wearRecord {
                record.items.removeAll { $0.id == recordItem.id }
            }
            context.delete(recordItem)
        }
        for outfitId in affectedOutfits {
            let descriptor = FetchDescriptor<Outfit>(predicate: #Predicate { $0.id == outfitId })
            if let outfit = try? context.fetch(descriptor).first,
               outfit.slots.allSatisfy({ $0.clothingItem == nil }) {
                context.delete(outfit)
            }
        }
    }

    var topCategory: Category? {
        category?.parent ?? category
    }

    var displayName: String {
        name.isEmpty ? (category?.name ?? "未命名") : name
    }
}
