import SwiftUI
import SwiftData

struct ClothingPickerView: View {
    var category: Category?
    var onSelect: (ClothingItem) -> Void

    @Query private var allItems: [ClothingItem]

    var body: some View {
        let items = filteredItems
        List(items) { item in
            HStack(spacing: 12) {
                ClothingThumbnailView(item: item)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.subheadline)
                    if let cat = item.category {
                        Text(cat.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(item)
            }
        }
        .navigationTitle(category?.name ?? "选择衣物")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredItems: [ClothingItem] {
        guard let category else { return allItems }
        return allItems.filter { item in
            item.category?.id == category.id ||
            item.category?.parent?.id == category.id
        }
    }
}
