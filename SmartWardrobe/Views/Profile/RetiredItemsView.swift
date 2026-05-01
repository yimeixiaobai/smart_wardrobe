import SwiftUI
import SwiftData

struct RetiredItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ClothingItem> { $0.status == "已淘汰" },
           sort: \ClothingItem.updatedAt, order: .reverse)
    private var retiredItems: [ClothingItem]

    @State private var itemToDelete: ClothingItem?
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if retiredItems.isEmpty {
                EmptyStateView(
                    icon: "archivebox",
                    title: "没有已淘汰的衣物",
                    message: "在衣橱中长按衣物可标记为淘汰"
                )
            } else {
                List {
                    ForEach(retiredItems) { item in
                        HStack(spacing: 12) {
                            ClothingThumbnailView(item: item)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .opacity(0.6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.subheadline)
                                if let cat = item.category?.name {
                                    Text(cat)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                itemToDelete = item
                                showDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                item.status = ClothingStatus.active.rawValue
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("已淘汰衣物")
        .navigationBarTitleDisplayMode(.inline)
        .alert("永久删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                if let item = itemToDelete {
                    let imgFile = item.imageFileName
                    let origFile = item.originalImageFileName
                    let thumbFile = item.thumbnailFileName
                    item.cleanupBeforeDelete(in: modelContext)
                    modelContext.delete(item)
                    modelContext.safeSave()
                    ImageStorageService.shared.deleteImages(
                        imageFileName: imgFile,
                        originalFileName: origFile,
                        thumbnailFileName: thumbFile
                    )
                }
            }
        } message: {
            Text("永久删除后不可恢复，确定吗？")
        }
    }
}
