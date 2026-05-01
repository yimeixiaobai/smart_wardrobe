import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "tag"
    var sortOrder: Int = 0
    var isSystem: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    var children: [Category] = []
    var parent: Category?

    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.category)
    var clothingItems: [ClothingItem] = []

    init(name: String, icon: String = "tag", sortOrder: Int = 0, isSystem: Bool = false, parent: Category? = nil) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.parent = parent
        self.createdAt = Date()
    }

    var isTopLevel: Bool {
        parent == nil
    }

    var sortedChildren: [Category] {
        children.sorted { $0.sortOrder < $1.sortOrder }
    }

    var itemCount: Int {
        if isTopLevel {
            let directCount = clothingItems.count
            let childrenCount = children.reduce(0) { $0 + $1.clothingItems.count }
            return directCount + childrenCount
        }
        return clothingItems.count
    }
}
