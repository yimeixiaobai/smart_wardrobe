import Foundation
import SwiftData

@Model
final class Outfit {
    var id: UUID = UUID()
    var name: String = ""
    var occasion: String?
    var notes: String?
    var backgroundStyle: String = "dark"
    var seasons: [String] = []
    var thumbnailFileName: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \OutfitSlot.outfit)
    var slots: [OutfitSlot] = []

    init(name: String = "") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var sortedSlots: [OutfitSlot] {
        slots.sorted { $0.zIndex < $1.zIndex }
    }

    var itemCount: Int {
        slots.count
    }

    @discardableResult
    static func createFromRecommendation(
        name: String,
        recommendation: OutfitRecommendationService.OutfitRecommendation,
        in context: ModelContext
    ) -> Outfit? {
        let validItems = recommendation.items
        guard !validItems.isEmpty else { return nil }

        let outfit = Outfit(name: name)
        outfit.occasion = recommendation.occasion
        outfit.notes = recommendation.reason
        context.insert(outfit)

        for (index, item) in validItems.enumerated() {
            let slot = OutfitSlot(
                clothingItem: item,
                positionX: 0.5,
                positionY: 0.1 + Double(index) / Double(max(validItems.count - 1, 1)) * 0.55,
                zIndex: index
            )
            context.insert(slot)
            outfit.slots.append(slot)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            return nil
        }
        return outfit
    }
}
