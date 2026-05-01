import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    @State private var selectedTopCategory: Category?
    @State private var selectedSubCategory: Category?
    @State private var searchText = ""
    /// 外部传入的导航目标（如从中央+导入后跳转）
    var navigateToItem: Binding<ClothingItem?> = .constant(nil)
    @State private var showFavoritesOnly = false
    @State private var showingAddSheet = false
    @State private var showingBatchImport = false
    @State private var showingTaobaoImport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topCategoryTabBar()
                Divider()
                if showFavoritesOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("只看收藏")
                            .font(.caption)
                        Spacer()
                        Button { showFavoritesOnly = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
                }
                mainContent()
            }
            .navigationTitle("衣橱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showFavoritesOnly.toggle()
                        } label: {
                            Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                                .foregroundStyle(showFavoritesOnly ? .red : .secondary)
                        }

                        Menu {
                            Button("添加单件", systemImage: "plus") {
                                showingAddSheet = true
                            }
                            Button("批量导入", systemImage: "photo.stack") {
                                showingBatchImport = true
                            }
                            Button("淘宝导入", systemImage: "cart") {
                                showingTaobaoImport = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索衣物")
            .navigationDestination(item: navigateToItem) { item in
                ClothingDetailView(item: item)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddClothingView(preselectedCategory: selectedSubCategory ?? selectedTopCategory) { item in
                    navigateToItem.wrappedValue = item
                }
            }
            .sheet(isPresented: $showingBatchImport) {
                BatchImportView(preselectedCategory: selectedSubCategory ?? selectedTopCategory)
            }
            .sheet(isPresented: $showingTaobaoImport) {
                TaobaoImportView(preselectedCategory: selectedSubCategory ?? selectedTopCategory)
            }
            .onAppear {
                if selectedTopCategory == nil {
                    selectedTopCategory = topCategories.first
                }
            }
        }
    }

    @ViewBuilder
    private func topCategoryTabBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(topCategories) { category in
                    let isSelected = selectedTopCategory?.id == category.id
                    VStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(.title3)
                        Text(category.name)
                            .font(.caption)
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        VStack {
                            Spacer()
                            if isSelected {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTopCategory = category
                            selectedSubCategory = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func mainContent() -> some View {
        HStack(spacing: 0) {
            if let top = selectedTopCategory, !top.sortedChildren.isEmpty {
                subcategorySidebar(for: top)
                Divider()
            }
            clothingGrid()
        }
    }

    @ViewBuilder
    private func subcategorySidebar(for topCategory: Category) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                sidebarItem(name: "全部", isSelected: selectedSubCategory == nil) {
                    selectedSubCategory = nil
                }
                ForEach(topCategory.sortedChildren) { sub in
                    sidebarItem(name: sub.name, isSelected: selectedSubCategory?.id == sub.id) {
                        selectedSubCategory = sub
                    }
                }
            }
        }
        .frame(width: 80)
        .background(Color(.systemGray6))
    }

    @ViewBuilder
    private func sidebarItem(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Text(name)
            .font(.subheadline)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color(.systemBackground) : Color.clear)
            .onTapGesture(perform: action)
    }

    @ViewBuilder
    private func clothingGrid() -> some View {
        ClothingGridContent(
            selectedTopCategory: selectedTopCategory,
            selectedSubCategory: selectedSubCategory,
            showFavoritesOnly: showFavoritesOnly,
            searchText: searchText
        )
    }
}

// MARK: - 独立子视图：仅当筛选条件变化时重新计算

/// 将过滤 + 网格渲染提取为独立视图，避免父视图无关状态（sheet/alert）
/// 变化时触发重新过滤和排序
private struct ClothingGridContent: View {
    let selectedTopCategory: Category?
    let selectedSubCategory: Category?
    let showFavoritesOnly: Bool
    let searchText: String
    @State private var showRetireHint = false
    @AppStorage("has_retired_before") private var hasRetiredBefore = false

    private var filteredItems: [ClothingItem] {
        var items: [ClothingItem] = []

        if let sub = selectedSubCategory {
            items = sub.clothingItems
        } else if let top = selectedTopCategory {
            var all = top.clothingItems
            for child in top.children {
                all.append(contentsOf: child.clothingItems)
            }
            items = all
        }

        items = items.filter { $0.status != ClothingStatus.retired.rawValue }

        if showFavoritesOnly {
            items = items.filter { $0.isFavorite }
        }

        if !searchText.isEmpty {
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.brand?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.notes?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.storageLocation?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        let items = filteredItems
        Group {
            if items.isEmpty {
                EmptyStateView(
                    icon: "tshirt",
                    title: "暂无衣物",
                    message: "点击右上角 + 添加你的第一件衣物"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(items) { item in
                            NavigationLink {
                                ClothingDetailView(item: item)
                            } label: {
                                ClothingGridCell(item: item)
                            }
                            .buttonStyle(GridCellButtonStyle())
                            .contextMenu {
                                Button {
                                    item.isFavorite.toggle()
                                } label: {
                                    Label(item.isFavorite ? "取消收藏" : "收藏", systemImage: item.isFavorite ? "heart.slash" : "heart")
                                }
                                if item.status == ClothingStatus.retired.rawValue {
                                    Button {
                                        item.status = ClothingStatus.active.rawValue
                                    } label: {
                                        Label("恢复使用", systemImage: "arrow.uturn.backward")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        item.status = ClothingStatus.retired.rawValue
                                        if !hasRetiredBefore {
                                            showRetireHint = true
                                            hasRetiredBefore = true
                                        }
                                    } label: {
                                        Label("淘汰", systemImage: "archivebox")
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .alert("已移入淘汰列表", isPresented: $showRetireHint) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("淘汰的衣物可在「我的 → 已淘汰衣物」中查看或永久删除")
        }
    }
}

struct ClothingGridCell: View {
    let item: ClothingItem

    /// 7 天内创建算"新品"
    private var isNew: Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return false }
        return item.createdAt > cutoff
    }

    private var isLentOut: Bool {
        item.status == ClothingStatus.lentOut.rawValue
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ClothingThumbnailView(item: item)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(isLentOut ? 0.45 : 1.0)

                if isLentOut {
                    Text("已借出")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.85))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                }

                // 收藏 + 新品角标
                VStack(alignment: .trailing, spacing: 4) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.red.opacity(0.85))
                            .clipShape(Circle())
                            .padding(6)
                    }
                    if isNew && !item.isFavorite {
                        Text("新")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
            }

            // 名称 + 颜色条
            VStack(spacing: 3) {
                if !item.name.isEmpty {
                    Text(item.name)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                // 衣物主色指示条
                if !item.colorHexValues.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(item.colorHexValues.prefix(5), id: \.self) { hex in
                            Color(hex: hex)
                                .frame(height: 3)
                        }
                    }
                    .clipShape(Capsule())
                    .frame(width: 32)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

/// 按压缩放反馈
private struct GridCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
