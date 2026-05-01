import Foundation
import SwiftData

@Model
final class WearRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var note: String?
    var mood: String?
    var occasion: String?

    @Relationship(deleteRule: .nullify)
    var outfit: Outfit?

    @Relationship(deleteRule: .cascade, inverse: \WearRecordItem.wearRecord)
    var items: [WearRecordItem] = []

    var createdAt: Date = Date()

    init(date: Date = Date()) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
    }

    var allClothingItems: [ClothingItem] {
        var result: [ClothingItem] = []
        if let outfit {
            result.append(contentsOf: outfit.slots.compactMap(\.clothingItem))
        }
        let directItems = items.compactMap(\.clothingItem)
        for item in directItems where !result.contains(where: { $0.id == item.id }) {
            result.append(item)
        }
        return result
    }

    var displayDate: String {
        ChineseDateFormatter.monthDayWeekday(date)
    }
}
