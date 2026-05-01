import SwiftUI
import SwiftData

// MARK: - 永久标签存储

enum SavedTagsStore {
    private static func key(_ name: String) -> String { "saved_tags_\(name)" }

    static func tags(for name: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(name)) ?? []
    }

    static func add(_ value: String, to name: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = tags(for: name)
        if !list.contains(trimmed) {
            list.append(trimmed)
            UserDefaults.standard.set(list, forKey: key(name))
        }
    }

    static func remove(_ value: String, from name: String) {
        var list = tags(for: name)
        list.removeAll { $0 == value }
        UserDefaults.standard.set(list, forKey: key(name))
    }
}

// MARK: - 编辑字段

private enum EditField: Identifiable {
    case notes, category, color, status, storageLocation
    case season, brand, size
    case material, collarType, sleeveLength, closureType, washingMethod
    case pantLength, skirtLength, heelHeight, bagSize
    case purchasePrice, purchaseDate, purchaseLink
    case tags

    var id: String { String(describing: self) }

    var title: String {
        switch self {
        case .notes: "备注"
        case .category: "分类"
        case .color: "颜色"
        case .status: "状态"
        case .storageLocation: "存放位置"
        case .season: "季节"
        case .brand: "品牌"
        case .size: "尺码"
        case .material: "材质"
        case .collarType: "领型"
        case .sleeveLength: "袖长"
        case .closureType: "闭合方式"
        case .washingMethod: "洗涤方式"
        case .pantLength: "裤长"
        case .skirtLength: "裙长"
        case .heelHeight: "跟高"
        case .bagSize: "包型"
        case .purchasePrice: "购买价格"
        case .purchaseDate: "购买时间"
        case .purchaseLink: "购买链接"
        case .tags: "单品标签"
        }
    }

    /// 弹出高度
    var sheetDetent: PresentationDetent {
        switch self {
        case .status, .sleeveLength, .washingMethod, .closureType,
             .pantLength, .skirtLength, .heelHeight, .bagSize:
            return .fraction(0.3)
        case .season, .notes, .size, .purchasePrice, .purchaseLink:
            return .fraction(0.35)
        case .material, .collarType, .brand, .storageLocation:
            return .fraction(0.45)
        case .category, .purchaseDate:
            return .medium
        case .color, .tags:
            return .fraction(0.55)
        }
    }
}

// MARK: - ClothingEditView

struct ClothingEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: ClothingItem

    @State private var activeField: EditField?

    private var topCat: String {
        item.topCategory?.name ?? ""
    }

    var body: some View {
        Form {
            Section("基本信息") {
                editRow(.notes) {
                    Text(item.notes ?? "请输入")
                        .foregroundStyle(item.notes == nil ? .tertiary : .secondary)
                }
                editRow(.category) {
                    Text(item.category?.name ?? "请选择")
                        .foregroundStyle(item.category == nil ? .tertiary : .secondary)
                }
                editRow(.color) {
                    HStack(spacing: 6) {
                        if !item.colorHexValues.isEmpty {
                            ColorDotView(hexValues: item.colorHexValues)
                        }
                        Text(item.colorStyle ?? "纯色")
                            .foregroundStyle(.secondary)
                    }
                }
                editRow(.status) {
                    Text(item.status)
                        .foregroundStyle(.secondary)
                }
                editRow(.storageLocation) {
                    Text(item.storageLocation ?? "请输入")
                        .foregroundStyle(item.storageLocation == nil ? .tertiary : .secondary)
                }
            }

            Section("季节") {
                editRow(.season) {
                    if item.seasons.isEmpty {
                        Text("请选择")
                            .foregroundStyle(.tertiary)
                    } else {
                        SeasonTagsView(seasons: item.seasons)
                    }
                }
            }

            Section("品牌与尺码") {
                editRow(.brand) {
                    Text(item.brand ?? "请输入")
                        .foregroundStyle(item.brand == nil ? .tertiary : .secondary)
                }
                editRow(.size) {
                    Text(item.size ?? "请输入")
                        .foregroundStyle(item.size == nil ? .tertiary : .secondary)
                }
            }

            Section("衣物详情") {
                // 通用：材质
                editRow(.material) {
                    Text(item.material ?? "请选择")
                        .foregroundStyle(item.material == nil ? .tertiary : .secondary)
                }

                // 上衣、连体装：领型
                if topCat == "上衣" || topCat == "连体装" {
                    editRow(.collarType) {
                        Text(item.collarType ?? "请选择")
                            .foregroundStyle(item.collarType == nil ? .tertiary : .secondary)
                    }
                }

                // 上衣、连体装：袖长
                if topCat == "上衣" || topCat == "连体装" {
                    editRow(.sleeveLength) {
                        Text(item.sleeveLength ?? "请选择")
                            .foregroundStyle(item.sleeveLength == nil ? .tertiary : .secondary)
                    }
                }

                // 裤子：裤长
                if topCat == "裤子" {
                    editRow(.pantLength) {
                        Text(item.pantLength ?? "请选择")
                            .foregroundStyle(item.pantLength == nil ? .tertiary : .secondary)
                    }
                }

                // 半身裙、连体装：裙长
                if topCat == "半身裙" || topCat == "连体装" {
                    editRow(.skirtLength) {
                        Text(item.skirtLength ?? "请选择")
                            .foregroundStyle(item.skirtLength == nil ? .tertiary : .secondary)
                    }
                }

                // 鞋：跟高
                if topCat == "鞋" {
                    editRow(.heelHeight) {
                        Text(item.heelHeight ?? "请选择")
                            .foregroundStyle(item.heelHeight == nil ? .tertiary : .secondary)
                    }
                }

                // 包：包型
                if topCat == "包" {
                    editRow(.bagSize) {
                        Text(item.bagSize ?? "请选择")
                            .foregroundStyle(item.bagSize == nil ? .tertiary : .secondary)
                    }
                }

                // 上衣、裤子、半身裙、连体装、鞋、包：闭合方式
                if ["上衣", "裤子", "半身裙", "连体装", "鞋", "包"].contains(topCat) {
                    editRow(.closureType) {
                        Text(item.closureType ?? "请选择")
                            .foregroundStyle(item.closureType == nil ? .tertiary : .secondary)
                    }
                }

                // 通用：洗涤方式
                editRow(.washingMethod) {
                    Text(item.washingMethod ?? "请选择")
                        .foregroundStyle(item.washingMethod == nil ? .tertiary : .secondary)
                }
            }

            Section("购买信息") {
                editRow(.purchasePrice) {
                    if let price = item.purchasePrice {
                        Text("¥ \(price, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("请输入")
                            .foregroundStyle(.tertiary)
                    }
                }
                editRow(.purchaseDate) {
                    if let date = item.purchaseDate {
                        Text(date, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("请选择")
                            .foregroundStyle(.tertiary)
                    }
                }
                editRow(.purchaseLink) {
                    Text(item.purchaseLink ?? "请输入")
                        .foregroundStyle(item.purchaseLink == nil ? .tertiary : .secondary)
                }
            }

            Section("单品标签") {
                editRow(.tags) {
                    if item.tags.isEmpty {
                        Text("请输入")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(item.tags.joined(separator: "、"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("编辑衣物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    item.updatedAt = Date()
                    dismiss()
                }
            }
        }
        .sheet(item: $activeField) { field in
            FieldSheet(field: field, item: item) {
                activeField = nil
            }
            .presentationDetents([field.sheetDetent])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func editRow<Content: View>(_ field: EditField, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(field.title)
            Spacer()
            trailing()
        }
        .contentShape(Rectangle())
        .onTapGesture { activeField = field }
    }
}

// MARK: - 底部弹出总入口

private struct FieldSheet: View {
    let field: EditField
    @Bindable var item: ClothingItem
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            sheetContent()
                .navigationTitle(field.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("确定", action: onDone)
                    }
                }
        }
    }

    @ViewBuilder
    private func sheetContent() -> some View {
        switch field {
        case .notes:
            NoteEditor(text: Binding(
                get: { item.notes ?? "" },
                set: { item.notes = $0.isEmpty ? nil : String($0.prefix(14)) }
            ))
        case .category:
            CategoryWheelPicker(selectedCategory: Binding(
                get: { item.category },
                set: { item.category = $0 }
            ))
        case .color:
            ColorEditor(
                hexValues: Binding(get: { item.colorHexValues }, set: { item.colorHexValues = $0 }),
                colorStyle: Binding(get: { item.colorStyle }, set: { item.colorStyle = $0 })
            )
        case .status:
            PillSelector(options: AppConstants.Status.all, selection: $item.status)
        case .storageLocation:
            TextWithSavedTags(
                placeholder: "输入存放位置",
                text: Binding(
                    get: { item.storageLocation ?? "" },
                    set: { item.storageLocation = $0.isEmpty ? nil : $0 }
                ),
                storeKey: "location"
            )
        case .season:
            SeasonEditor(seasons: Binding(get: { item.seasons }, set: { item.seasons = $0 }))
        case .brand:
            TextWithSavedTags(
                placeholder: "输入品牌名称",
                text: Binding(
                    get: { item.brand ?? "" },
                    set: { item.brand = $0.isEmpty ? nil : $0 }
                ),
                storeKey: "brand"
            )
        case .size:
            NoteEditor(text: Binding(
                get: { item.size ?? "" },
                set: { item.size = $0.isEmpty ? nil : $0 }
            ), placeholder: "输入尺码，如 M / 170/88A")
        case .material:
            ChipGridSelector(
                options: AppConstants.Material.all,
                selection: Binding(get: { item.material }, set: { item.material = $0 })
            )
        case .collarType:
            ChipGridSelector(
                options: AppConstants.CollarType.all,
                selection: Binding(get: { item.collarType }, set: { item.collarType = $0 })
            )
        case .sleeveLength:
            PillSelector(
                options: AppConstants.SleeveLength.all,
                selection: Binding(
                    get: { item.sleeveLength ?? "" },
                    set: { item.sleeveLength = $0.isEmpty ? nil : $0 }
                )
            )
        case .closureType:
            PillSelector(
                options: item.topCategory?.name == "鞋"
                    ? AppConstants.ShoeClosureType.all
                    : AppConstants.ClosureType.all,
                selection: Binding(
                    get: { item.closureType ?? "" },
                    set: { item.closureType = $0.isEmpty ? nil : $0 }
                )
            )
        case .washingMethod:
            PillSelector(
                options: AppConstants.WashingMethod.all,
                selection: Binding(
                    get: { item.washingMethod ?? "" },
                    set: { item.washingMethod = $0.isEmpty ? nil : $0 }
                )
            )
        case .pantLength:
            PillSelector(
                options: AppConstants.PantLength.all,
                selection: Binding(
                    get: { item.pantLength ?? "" },
                    set: { item.pantLength = $0.isEmpty ? nil : $0 }
                )
            )
        case .skirtLength:
            PillSelector(
                options: AppConstants.SkirtLength.all,
                selection: Binding(
                    get: { item.skirtLength ?? "" },
                    set: { item.skirtLength = $0.isEmpty ? nil : $0 }
                )
            )
        case .heelHeight:
            PillSelector(
                options: AppConstants.HeelHeight.all,
                selection: Binding(
                    get: { item.heelHeight ?? "" },
                    set: { item.heelHeight = $0.isEmpty ? nil : $0 }
                )
            )
        case .bagSize:
            PillSelector(
                options: AppConstants.BagSize.all,
                selection: Binding(
                    get: { item.bagSize ?? "" },
                    set: { item.bagSize = $0.isEmpty ? nil : $0 }
                )
            )
        case .purchasePrice:
            PriceEditor(price: Binding(
                get: { item.purchasePrice },
                set: { item.purchasePrice = $0 }
            ))
        case .purchaseDate:
            DateEditor(date: Binding(
                get: { item.purchaseDate ?? Date() },
                set: { item.purchaseDate = $0 }
            ))
        case .purchaseLink:
            NoteEditor(
                text: Binding(
                    get: { item.purchaseLink ?? "" },
                    set: { item.purchaseLink = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "粘贴购买链接",
                keyboard: .URL
            )
        case .tags:
            TagsEditorView(
                tags: Binding(get: { item.tags }, set: { item.tags = $0 }),
                storeKey: "item_tag"
            )
        }
    }
}

// MARK: - 1) 文字输入（备注、尺码、链接）

private struct NoteEditor: View {
    @Binding var text: String
    var placeholder: String = "请输入"
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .font(.body)
            if placeholder.contains("14") || placeholder == "请输入" {
                // 备注才显示计数
            }
        }
        .padding()
        .onAppear { focused = true }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 2) 横排药丸选择器（少量选项：状态3、袖长5、闭合6、洗涤4）

private struct PillSelector: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack {
            FlowLayout(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let isOn = selection == option
                    Text(option)
                        .font(.subheadline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(isOn ? Color.accentColor : Color(.systemGray6))
                        .foregroundStyle(isOn ? .white : .primary)
                        .clipShape(Capsule())
                        .onTapGesture { selection = option }
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 3) 网格标签选择器（中等数量：材质12、领型10）

private struct ChipGridSelector: View {
    let options: [String]
    @Binding var selection: String?

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let isOn = selection == option
                    Text(option)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isOn ? Color.accentColor : Color(.systemGray6))
                        .foregroundStyle(isOn ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            selection = isOn ? nil : option
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - 4) 季节多选

private struct SeasonEditor: View {
    @Binding var seasons: [String]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppConstants.Seasons.all, id: \.self) { season in
                let isOn = seasons.contains(season)
                VStack(spacing: 6) {
                    Image(systemName: seasonIcon(season))
                        .font(.title2)
                    Text(season)
                        .font(.subheadline)
                }
                .frame(width: 64, height: 72)
                .background(isOn ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5)
                )
                .onTapGesture {
                    if isOn { seasons.removeAll { $0 == season } }
                    else { seasons.append(season) }
                }
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func seasonIcon(_ s: String) -> String {
        switch s {
        case "春": return "leaf"
        case "夏": return "sun.max"
        case "秋": return "wind"
        case "冬": return "snowflake"
        default: return "circle"
        }
    }
}

// MARK: - 5) 文字输入 + 已存标签（存放位置、品牌）

private struct TextWithSavedTags: View {
    let placeholder: String
    @Binding var text: String
    let storeKey: String

    @FocusState private var focused: Bool
    @State private var savedTags: [String] = []
    @State private var inputText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 输入框 + 保存按钮
            HStack(spacing: 10) {
                TextField(placeholder, text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { commitInput() }

                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        commitInput()
                    } label: {
                        Text("保存")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)

            // 已存标签
            if !savedTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("快速选择")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    FlowLayout(spacing: 8) {
                        ForEach(savedTags, id: \.self) { tag in
                            let isOn = text == tag
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.subheadline)
                                // 长按删除提示
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isOn ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .foregroundStyle(isOn ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                            .onTapGesture {
                                text = tag
                                inputText = tag
                            }
                            .contextMenu {
                                Button("删除标签", role: .destructive) {
                                    SavedTagsStore.remove(tag, from: storeKey)
                                    savedTags = SavedTagsStore.tags(for: storeKey)
                                    if text == tag { text = "" ; inputText = "" }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            inputText = text
            savedTags = SavedTagsStore.tags(for: storeKey)
            focused = true
        }
    }

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        text = trimmed
        SavedTagsStore.add(trimmed, to: storeKey)
        savedTags = SavedTagsStore.tags(for: storeKey)
    }
}

// MARK: - 6) 价格输入

private struct PriceEditor: View {
    @Binding var price: Double?
    @State private var priceText = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("¥")
                .font(.title)
                .foregroundStyle(.secondary)
            TextField("0.00", text: $priceText)
                .font(.title2)
                .keyboardType(.decimalPad)
                .focused($focused)
                .onChange(of: priceText) { _, v in
                    price = Double(v)
                }
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            if let p = price { priceText = String(format: "%.2f", p) }
            focused = true
        }
    }
}

// MARK: - 7) 日期选择

private struct DateEditor: View {
    @Binding var date: Date

    var body: some View {
        DatePicker("", selection: $date, displayedComponents: .date)
            .datePickerStyle(.wheel)
            .labelsHidden()
    }
}

// MARK: - 8) 颜色编辑

private struct ColorEditor: View {
    @Binding var hexValues: [String]
    @Binding var colorStyle: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("样式", selection: Binding(
                    get: { colorStyle ?? "纯色" },
                    set: { colorStyle = $0 }
                )) {
                    ForEach(AppConstants.ColorStyle.all, id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ColorPickerGridView(selectedHexValues: $hexValues)
                    .padding(.horizontal)
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - 9) 单品标签编辑（输入 + 已存标签 + 当前标签管理）

private struct TagsEditorView: View {
    @Binding var tags: [String]
    let storeKey: String

    @State private var inputText = ""
    @State private var savedTags: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 当前衣物标签
                if !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已添加")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.subheadline)
                                    Button {
                                        tags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // 输入新标签
                HStack(spacing: 10) {
                    TextField("输入标签", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { addTag() }

                    Button {
                        addTag()
                    } label: {
                        Text("添加")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color(.systemGray5) : Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)

                // 可用标签库
                let available = savedTags.filter { !tags.contains($0) }
                if !available.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标签库（点击添加）")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(available, id: \.self) { tag in
                                Text(tag)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        if !tags.contains(tag) { tags.append(tag) }
                                    }
                                    .contextMenu {
                                        Button("从标签库删除", role: .destructive) {
                                            SavedTagsStore.remove(tag, from: storeKey)
                                            savedTags = SavedTagsStore.tags(for: storeKey)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 16)
        }
        .onAppear {
            savedTags = SavedTagsStore.tags(for: storeKey)
            focused = true
        }
    }

    private func addTag() {
        let tag = inputText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        if !tags.contains(tag) { tags.append(tag) }
        SavedTagsStore.add(tag, to: storeKey)
        savedTags = SavedTagsStore.tags(for: storeKey)
        inputText = ""
    }
}

// MARK: - 10) 分类双列滚轮

private struct CategoryWheelPicker: View {
    @Binding var selectedCategory: Category?

    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    @State private var topIndex = 0
    @State private var subIndex = 0

    private var subs: [Category] {
        guard topCategories.indices.contains(topIndex) else { return [] }
        return topCategories[topIndex].sortedChildren
    }

    var body: some View {
        VStack(spacing: 0) {
            // 当前选中
            HStack(spacing: 6) {
                if topCategories.indices.contains(topIndex) {
                    Text(topCategories[topIndex].name)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if subs.indices.contains(subIndex) {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(subs[subIndex].name)
                            .font(.subheadline)
                    }
                }
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 10)

            Divider()

            HStack(spacing: 0) {
                Picker("", selection: $topIndex) {
                    ForEach(Array(topCategories.enumerated()), id: \.offset) { i, c in
                        Text(c.name).tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity).clipped()

                Picker("", selection: $subIndex) {
                    ForEach(Array(subs.enumerated()), id: \.offset) { i, c in
                        Text(c.name).tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity).clipped()
            }
        }
        .onAppear { initPicker() }
        .onChange(of: topIndex) { _, _ in
            subIndex = 0
            sync()
        }
        .onChange(of: subIndex) { _, _ in sync() }
    }

    private func sync() {
        if subs.indices.contains(subIndex) {
            selectedCategory = subs[subIndex]
        }
    }

    private func initPicker() {
        guard let cur = selectedCategory, let parent = cur.parent else { return }
        if let ti = topCategories.firstIndex(where: { $0.id == parent.id }) {
            topIndex = ti
            if let si = topCategories[ti].sortedChildren.firstIndex(where: { $0.id == cur.id }) {
                subIndex = si
            }
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private struct R { var size: CGSize; var positions: [CGPoint] }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> R {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 {
                x = 0; y += lineH + spacing; lineH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineH = max(lineH, s.height)
            x += s.width + spacing
            maxX = max(maxX, x)
        }
        return R(size: CGSize(width: maxX, height: y + lineH), positions: positions)
    }
}

// MARK: - 保留供外部引用

struct ColorEditView: View {
    @Binding var selectedHexValues: [String]
    @Binding var colorStyle: String?

    var body: some View {
        Form {
            Section("颜色样式") {
                Picker("样式", selection: Binding(
                    get: { colorStyle ?? "纯色" },
                    set: { colorStyle = $0 }
                )) {
                    ForEach(AppConstants.ColorStyle.all, id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("选择颜色") {
                ColorPickerGridView(selectedHexValues: $selectedHexValues)
            }
        }
        .navigationTitle("颜色")
    }
}

struct CategorySelectionView: View {
    @Binding var selectedCategory: Category?
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    @State private var topIndex = 0
    @State private var subIndex = 0

    private var subs: [Category] {
        guard topCategories.indices.contains(topIndex) else { return [] }
        return topCategories[topIndex].sortedChildren
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if topCategories.indices.contains(topIndex) {
                    Text(topCategories[topIndex].name)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if subs.indices.contains(subIndex) {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(subs[subIndex].name).font(.subheadline)
                    }
                }
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 12)
            Divider()
            HStack(spacing: 0) {
                Picker("", selection: $topIndex) {
                    ForEach(Array(topCategories.enumerated()), id: \.offset) { i, c in
                        Text(c.name).tag(i)
                    }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
                Picker("", selection: $subIndex) {
                    ForEach(Array(subs.enumerated()), id: \.offset) { i, c in
                        Text(c.name).tag(i)
                    }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
            }
        }
        .navigationTitle("选择分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("确定") {
                    if subs.indices.contains(subIndex) { selectedCategory = subs[subIndex] }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard let cur = selectedCategory, let parent = cur.parent else { return }
            if let ti = topCategories.firstIndex(where: { $0.id == parent.id }) {
                topIndex = ti
                if let si = topCategories[ti].sortedChildren.firstIndex(where: { $0.id == cur.id }) {
                    subIndex = si
                }
            }
        }
        .onChange(of: topIndex) { _, _ in subIndex = 0 }
        .onChange(of: subIndex) { _, _ in
            if subs.indices.contains(subIndex) { selectedCategory = subs[subIndex] }
        }
    }
}
