import SwiftUI

struct WearRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: WearRecord
    @State private var showingDeleteAlert = false

    private let imageService = ImageStorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Date header
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.accentColor)
                    Text(ChineseDateFormatter.fullDateWeekday(record.date))
                        .font(.title3.bold())
                }
                .padding(.horizontal)

                // Tags
                HStack(spacing: 8) {
                    if let occasion = record.occasion {
                        TagPill(text: occasion, color: .blue)
                    }
                    if let mood = record.mood {
                        Text(mood)
                            .font(.title3)
                    }
                }
                .padding(.horizontal)

                // Items
                let items = record.allClothingItems
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("穿搭单品（\(items.count) 件）")
                            .font(.subheadline.bold())
                            .padding(.horizontal)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(items, id: \.id) { item in
                                VStack(spacing: 4) {
                                    ClothingThumbnailView(item: item)
                                        .frame(height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(.systemGray6))
                                        )
                                    Text(item.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Note
                if let note = record.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注")
                            .font(.subheadline.bold())
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("穿搭详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text("删除后不可恢复，确定要删除这条穿搭记录吗？")
        }
    }

    private func deleteRecord() {
        for item in record.allClothingItems {
            item.wearCount = max(0, item.wearCount - 1)
        }
        modelContext.delete(record)
        dismiss()
    }
}
