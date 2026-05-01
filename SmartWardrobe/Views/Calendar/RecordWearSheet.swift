import SwiftUI
import SwiftData

struct RecordWearSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query(sort: \WearRecord.date) private var existingRecords: [WearRecord]
    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    @State private var date: Date
    @State private var mode: RecordMode = .items
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectedOutfitID: UUID?
    @State private var occasion: String?
    @State private var mood: String?
    @State private var note: String = ""
    @State private var selectedCategoryIndex: Int = 0
    @State private var showingDatePicker = false
    @State private var showingDuplicateAlert = false

    enum RecordMode: String, CaseIterable {
        case items = "选择单品"
        case outfit = "选择搭配"
    }

    private var editingRecord: WearRecord?

    init(date: Date = Date(), existingRecord: WearRecord? = nil) {
        let d = Calendar.current.startOfDay(for: date)
        _date = State(initialValue: d)
        self.editingRecord = existingRecord
        if let record = existingRecord {
            _occasion = State(initialValue: record.occasion)
            _mood = State(initialValue: record.mood)
            _note = State(initialValue: record.note ?? "")
            if record.outfit != nil {
                _mode = State(initialValue: .outfit)
                _selectedOutfitID = State(initialValue: record.outfit?.id)
            } else {
                _mode = State(initialValue: .items)
                _selectedItemIDs = State(initialValue: Set(record.items.compactMap { $0.clothingItem?.id }))
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dateSection()
                modeSection()

                switch mode {
                case .items:
                    categoryFilter()
                    itemsGrid()
                case .outfit:
                    outfitGrid()
                }

                occasionSection()
                moodSection()
                noteSection()
            }
            .padding()
        }
        .navigationTitle("记录穿搭")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
            }
        }
        .alert("当天已有记录", isPresented: $showingDuplicateAlert) {
            Button("覆盖") { saveForce() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该日期已有穿搭记录，是否覆盖？")
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("选择日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showingDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func dateSection() -> some View {
        Button {
            showingDatePicker = true
        } label: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text(ChineseDateFormatter.fullDateWeekday(date))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modeSection() -> some View {
        Picker("模式", selection: $mode) {
            ForEach(RecordMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func categoryFilter() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryFilterChip(name: "全部", isSelected: selectedCategoryIndex == 0) {
                    selectedCategoryIndex = 0
                }
                ForEach(Array(topCategories.enumerated()), id: \.element.id) { index, cat in
                    CategoryFilterChip(name: cat.name, isSelected: selectedCategoryIndex == index + 1) {
                        selectedCategoryIndex = index + 1
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemsGrid() -> some View {
        let filtered = filteredItems()
        VStack(alignment: .leading, spacing: 8) {
            Text("已选 \(selectedItemIDs.count) 件")
                .font(.caption)
                .foregroundStyle(.secondary)

            MultiSelectClothingGrid(items: filtered, selectedIDs: $selectedItemIDs)
        }
    }

    @ViewBuilder
    private func outfitGrid() -> some View {
        if outfits.isEmpty {
            EmptyStateView(icon: "square.on.square", title: "暂无搭配", message: "请先创建搭配方案")
                .padding(.vertical, 40)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(outfits) { outfit in
                    let isSelected = selectedOutfitID == outfit.id
                    Button {
                        selectedOutfitID = isSelected ? nil : outfit.id
                    } label: {
                        OutfitCardView(outfit: outfit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .overlay(alignment: .topTrailing) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white, Color.accentColor)
                                        .font(.title3)
                                        .offset(x: -4, y: 4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func occasionSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("场合")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppConstants.Occasion.all, id: \.self) { occ in
                        let isSelected = occasion == occ
                        Button {
                            occasion = isSelected ? nil : occ
                        } label: {
                            Text(occ)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moodSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("心情")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppConstants.Mood.all, id: \.name) { m in
                        let isSelected = mood == m.emoji
                        Button {
                            mood = isSelected ? nil : m.emoji
                        } label: {
                            VStack(spacing: 2) {
                                Text(m.emoji)
                                    .font(.title2)
                                Text(m.name)
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(.subheadline.bold())

            TextField("今天的穿搭感受...", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Logic

    private var canSave: Bool {
        switch mode {
        case .items: return !selectedItemIDs.isEmpty
        case .outfit: return selectedOutfitID != nil
        }
    }

    private func filteredItems() -> [ClothingItem] {
        let active = allItems.filter { $0.status != ClothingStatus.retired.rawValue }
        if selectedCategoryIndex == 0 { return active }
        let catIndex = selectedCategoryIndex - 1
        guard catIndex < topCategories.count else { return active }
        let cat = topCategories[catIndex]
        return active.filter { $0.topCategory?.id == cat.id }
    }

    private func save() {
        if editingRecord != nil {
            saveForce()
            return
        }
        let dayStart = Calendar.current.startOfDay(for: date)
        if existingRecords.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) }) {
            showingDuplicateAlert = true
            return
        }
        saveForce()
    }

    private func saveForce() {
        let dayStart = Calendar.current.startOfDay(for: date)

        // Remove existing record for this day if any
        if let existing = existingRecords.first(where: { Calendar.current.isDate($0.date, inSameDayAs: dayStart) }) {
            for item in existing.allClothingItems {
                item.wearCount = max(0, item.wearCount - 1)
            }
            modelContext.delete(existing)
        }

        let record = WearRecord(date: date)
        record.occasion = occasion
        record.mood = mood
        record.note = note.isEmpty ? nil : note

        switch mode {
        case .outfit:
            if let outfitID = selectedOutfitID {
                record.outfit = outfits.first { $0.id == outfitID }
            }
        case .items:
            for id in selectedItemIDs {
                if let item = allItems.first(where: { $0.id == id }) {
                    let recordItem = WearRecordItem(clothingItem: item)
                    modelContext.insert(recordItem)
                    record.items.append(recordItem)
                }
            }
        }

        modelContext.insert(record)

        // Increment wear counts
        for item in record.allClothingItems {
            item.wearCount += 1
        }

        modelContext.safeSave()
        dismiss()
    }
}

// MARK: - Category Filter Chip

struct CategoryFilterChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
