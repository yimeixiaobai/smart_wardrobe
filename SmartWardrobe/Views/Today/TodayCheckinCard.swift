import SwiftUI
import SwiftData

/// 今日穿搭打卡卡
/// - 已记录：紧凑展示今天穿了什么
/// - 未记录：大按钮引导记录
struct TodayCheckinCard: View {
    let records: [WearRecord]
    let allItems: [ClothingItem]

    @State private var showingRecordSheet = false

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayRecord: WearRecord? {
        records.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日穿搭", systemImage: "checkmark.seal")
                    .font(.headline)
                Spacer()
                if todayRecord != nil {
                    Button {
                        showingRecordSheet = true
                    } label: {
                        Text("编辑")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let record = todayRecord {
                recordContent(record)
            } else {
                emptyContent()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            // 左侧彩色指示条
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(todayRecord != nil ? Color.green : Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 12)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .sheet(isPresented: $showingRecordSheet) {
            NavigationStack {
                RecordWearSheet(date: today, existingRecord: todayRecord)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func emptyContent() -> some View {
        Button {
            showingRecordSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("记录今天穿了什么")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.accentColor.opacity(0.1))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func recordContent(_ record: WearRecord) -> some View {
        let items = record.allClothingItems

        VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.id) { item in
                            ClothingThumbnailView(item: item)
                                .frame(width: 64, height: 72)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if let occasion = record.occasion {
                    TagPill(text: occasion, color: .blue)
                }
                if let mood = record.mood {
                    Text(mood).font(.subheadline)
                }
                Spacer()
                Text("\(items.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
