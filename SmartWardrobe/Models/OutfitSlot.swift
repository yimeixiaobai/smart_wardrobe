import Foundation
import SwiftData

@Model
final class OutfitSlot {
    var id: UUID = UUID()
    var positionX: Double = 0.5
    var positionY: Double = 0.5
    var scale: Double = 1.0
    var rotation: Double = 0.0
    var zIndex: Int = 0

    @Relationship(deleteRule: .nullify)
    var outfit: Outfit?

    @Relationship(deleteRule: .nullify)
    var clothingItem: ClothingItem?

    init(clothingItem: ClothingItem? = nil, positionX: Double = 0.5, positionY: Double = 0.5, zIndex: Int = 0) {
        self.id = UUID()
        self.clothingItem = clothingItem
        self.positionX = positionX
        self.positionY = positionY
        self.zIndex = zIndex
    }
}
