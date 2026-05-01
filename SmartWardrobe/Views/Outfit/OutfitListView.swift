import SwiftUI
import SwiftData

struct OutfitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @State private var showingCanvas = false
    @State private var outfitToDelete: Outfit?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if outfits.isEmpty {
                EmptyStateView(
                    icon: "square.on.square",
                    title: "暂无搭配",
                    message: "点击右上角 + 创建你的第一套搭配"
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        ForEach(outfits) { outfit in
                            NavigationLink {
                                OutfitCanvasView(outfit: outfit)
                            } label: {
                                OutfitCardView(outfit: outfit)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    outfitToDelete = outfit
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("删除搭配", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCanvas = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showingCanvas) {
            NavigationStack {
                OutfitCanvasView(outfit: nil)
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                if let outfit = outfitToDelete {
                    let thumbName = outfit.thumbnailFileName
                    modelContext.delete(outfit)
                    modelContext.safeSave()
                    if let thumbName {
                        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("Thumbnails", isDirectory: true)
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(thumbName))
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除「\(outfitToDelete?.name ?? "")」吗？此操作不可恢复。")
        }
    }
}

struct OutfitCardView: View {
    let outfit: Outfit
    private let imageService = ImageStorageService.shared

    private var backgroundColor: Color {
        AppConstants.CanvasBackground.styles
            .first(where: { $0.name == outfit.backgroundStyle })?.color
            ?? AppConstants.CanvasBackground.styles[0].color
    }

    /// 浅色背景用深色文字，深色背景用浅色文字
    private var isLightBackground: Bool {
        let idx = AppConstants.CanvasBackground.styles
            .firstIndex(where: { $0.name == outfit.backgroundStyle }) ?? 0
        return idx < 4
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )

                if let thumbName = outfit.thumbnailFileName,
                   let image = imageService.loadThumbnail(fileName: thumbName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Show mini previews of items
                    VStack(spacing: 4) {
                        ForEach(outfit.sortedSlots.prefix(3)) { slot in
                            if let item = slot.clothingItem {
                                ClothingThumbnailView(item: item)
                                    .frame(height: 40)
                            }
                        }
                        if outfit.itemCount > 3 {
                            Text("+\(outfit.itemCount - 3)")
                                .font(.caption2)
                                .foregroundStyle(isLightBackground ? Color.secondary : Color.white)
                        }
                    }
                    .padding(8)
                }
            }

            HStack(spacing: 4) {
                Text(outfit.name.isEmpty ? "未命名搭配" : outfit.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // 配色评分角标
                if outfit.itemCount >= 2 {
                    let hexColors = outfit.sortedSlots.compactMap { $0.clothingItem?.colorHexValues }
                    let harmony = ColorHarmonyService.analyze(hexColors: hexColors)
                    Text("\(harmony.score)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(harmony.level.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(harmony.level.color.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Text("\(outfit.itemCount) 件单品")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
