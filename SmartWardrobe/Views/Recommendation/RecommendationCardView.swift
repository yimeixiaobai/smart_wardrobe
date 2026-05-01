import SwiftUI

struct RecommendationCardView: View {
    let recommendation: OutfitRecommendationService.OutfitRecommendation
    var onSaveAsOutfit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recommendation.items, id: \.id) { item in
                        VStack(spacing: 4) {
                            ClothingThumbnailView(item: item)
                                .frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                )

                            Text(item.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 70)
                        }
                    }
                }
            }

            // Color harmony badge + occasion
            HStack(spacing: 8) {
                let hexColors = recommendation.items.map(\.colorHexValues)
                let harmony = ColorHarmonyService.analyze(hexColors: hexColors)

                HStack(spacing: 4) {
                    Image(systemName: harmony.level.icon)
                        .font(.caption2)
                    Text("\(harmony.score)分")
                        .font(.caption)
                }
                .foregroundStyle(harmony.level.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(harmony.level.color.opacity(0.1))
                .clipShape(Capsule())

                TagPill(text: recommendation.occasion, color: .blue)

                Spacer()
            }

            // Reason
            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Styling tip
            if let tip = recommendation.stylingTip, !tip.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Unmatched warning
            if !recommendation.unmatchedIds.isEmpty {
                Text("部分推荐无法匹配衣物")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Action buttons
            if let onSaveAsOutfit {
                HStack {
                    Spacer()
                    Button {
                        onSaveAsOutfit()
                    } label: {
                        Label("加入穿搭", systemImage: "square.on.square")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
