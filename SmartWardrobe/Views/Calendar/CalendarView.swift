import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WearRecord.date, order: .reverse) private var allRecords: [WearRecord]

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingRecordSheet = false

    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthNavigation()
                weekdayHeader()
                calendarGrid()
                Divider().padding(.horizontal)
                selectedDayContent()
            }
            .padding(.bottom, 20)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedDate = calendar.startOfDay(for: Date())
                    displayedMonth = Date()
                    showingRecordSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingRecordSheet) {
            NavigationStack {
                RecordWearSheet(date: selectedDate)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Month Navigation

    @ViewBuilder
    private func monthNavigation() -> some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            Text(ChineseDateFormatter.yearMonth(displayedMonth))
                .font(.title3.bold())

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Weekday Header

    @ViewBuilder
    private func weekdayHeader() -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private func calendarGrid() -> some View {
        let days = daysInMonth()
        let recordDates = recordDateSet()

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            let today = calendar.startOfDay(for: Date())
            ForEach(days, id: \.self) { day in
                if let day {
                    let isToday = calendar.isDateInToday(day)
                    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let hasRecord = recordDates.contains(calendar.startOfDay(for: day))
                    let isFuture = calendar.startOfDay(for: day) > today

                    Button {
                        selectedDate = calendar.startOfDay(for: day)
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundStyle(isFuture ? Color.gray.opacity(0.3) : dayTextColor(isToday: isToday, isSelected: isSelected))

                            Circle()
                                .fill(hasRecord ? Color.accentColor : Color.clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected && !isFuture ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Selected Day Content

    @ViewBuilder
    private func selectedDayContent() -> some View {
        let record = recordForDate(selectedDate)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ChineseDateFormatter.monthDayWeekday(selectedDate))
                    .font(.headline)
                Spacer()
                if record == nil && calendar.startOfDay(for: selectedDate) <= calendar.startOfDay(for: Date()) {
                    Button {
                        showingRecordSheet = true
                    } label: {
                        Label("记录穿搭", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)

            if let record {
                WearRecordCardView(record: record, onDelete: {
                    deleteRecord(record)
                })
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tshirt")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("这天没有穿搭记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Helpers

    private func dayTextColor(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return .accentColor }
        if isToday { return .accentColor }
        return .primary
    }

    private func moveMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newMonth
            }
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        let weekdayOffset = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: weekdayOffset)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }

        return days
    }

    private func recordDateSet() -> Set<Date> {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return [] }

        return Set(
            allRecords
                .filter { $0.date >= monthStart && $0.date < monthEnd }
                .map { calendar.startOfDay(for: $0.date) }
        )
    }

    private func recordForDate(_ date: Date) -> WearRecord? {
        let dayStart = calendar.startOfDay(for: date)
        return allRecords.first { calendar.isDate($0.date, inSameDayAs: dayStart) }
    }

    private func deleteRecord(_ record: WearRecord) {
        // Decrement wear counts
        for item in record.allClothingItems {
            item.wearCount = max(0, item.wearCount - 1)
        }
        modelContext.delete(record)
        modelContext.safeSave()
    }
}

// MARK: - Wear Record Card

struct WearRecordCardView: View {
    let record: WearRecord
    var onDelete: (() -> Void)?

    private let imageService = ImageStorageService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Outfit name or items
            if let outfit = record.outfit {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(outfit.name.isEmpty ? "未命名搭配" : outfit.name)
                        .font(.subheadline.bold())
                }
            }

            // Item thumbnails
            let clothingItems = record.allClothingItems
            if !clothingItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clothingItems, id: \.id) { item in
                            ClothingThumbnailView(item: item)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                }
            }

            // Tags row
            HStack(spacing: 8) {
                if let occasion = record.occasion {
                    TagPill(text: occasion, color: .blue)
                }
                if let mood = record.mood {
                    Text(mood)
                        .font(.subheadline)
                }
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct TagPill: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
