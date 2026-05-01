import SwiftUI

struct ClothingThumbnailView: View {
    let item: ClothingItem
    private let imageService = ImageStorageService.shared

    var body: some View {
        Group {
            if let thumbName = item.thumbnailFileName,
               let image = imageService.loadThumbnail(fileName: thumbName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let imgName = item.imageFileName,
                      let image = imageService.loadImage(fileName: imgName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                    Image(systemName: "tshirt")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ColorDotView: View {
    let hexValues: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(hexValues.prefix(5), id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
            }
        }
    }
}

struct SeasonTagsView: View {
    let seasons: [String]
    var selectable: Bool = false
    var onToggle: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppConstants.Seasons.all, id: \.self) { season in
                let isSelected = seasons.contains(season)
                Text(season)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                    )
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .onTapGesture {
                        onToggle?(season)
                    }
                    .allowsHitTesting(selectable)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
