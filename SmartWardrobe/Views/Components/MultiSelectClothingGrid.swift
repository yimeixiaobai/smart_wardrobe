import SwiftUI
import SwiftData

struct MultiSelectClothingGrid: View {
    let items: [ClothingItem]
    @Binding var selectedIDs: Set<UUID>

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items, id: \.id) { item in
                let isSelected = selectedIDs.contains(item.id)

                Button {
                    if isSelected {
                        selectedIDs.remove(item.id)
                    } else {
                        selectedIDs.insert(item.id)
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 4) {
                            ClothingThumbnailView(item: item)
                                .frame(height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(item.displayName)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.title3)
                                .offset(x: 4, y: -4)
                        }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
