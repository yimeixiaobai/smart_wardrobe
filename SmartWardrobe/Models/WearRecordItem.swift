import Foundation
import SwiftData

@Model
final class WearRecordItem {
    var id: UUID = UUID()

    @Relationship(deleteRule: .nullify)
    var wearRecord: WearRecord?

    @Relationship(deleteRule: .nullify)
    var clothingItem: ClothingItem?

    init(clothingItem: ClothingItem? = nil) {
        self.id = UUID()
        self.clothingItem = clothingItem
    }
}
