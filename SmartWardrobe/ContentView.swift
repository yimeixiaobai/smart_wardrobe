import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if sizeClass == .compact {
                MainTabView()
            } else {
                iPadSplitView()
            }
        }
        .onAppear {
            CategorySeeder.seedIfNeeded(context: modelContext)
        }
    }

    // MARK: - iPad SplitView

    @ViewBuilder
    private func iPadSplitView() -> some View {
        NavigationSplitView {
            List {
                NavigationLink { TodayView() } label: {
                    Label("今天", systemImage: "sun.max")
                }
                NavigationLink { WardrobeView() } label: {
                    Label("衣橱", systemImage: "tshirt")
                }
                NavigationLink { OutfitsTab() } label: {
                    Label("穿搭", systemImage: "square.on.square")
                }
                NavigationLink { ProfileView() } label: {
                    Label("我的", systemImage: "person")
                }
            }
            .navigationTitle("智能衣橱")
        } detail: {
            TodayView()
        }
    }
}

// MARK: - MainTabView（iPhone）

/// 4 tab + 中央浮动加号按钮（自定义 TabBar）
/// - 点击 + 弹出三个选项（拍照 / 相册 / 淘宝），不再需要长按
private struct MainTabView: View {
    @State private var selectedTab: Tab = .today
    @State private var showingAddOptions = false
    @State private var showingAddSheet = false
    @State private var showingBatchImport = false
    @State private var showingTaobaoImport = false
    @State private var savedItemForDetail: ClothingItem?

    enum Tab: Int, CaseIterable {
        case today, wardrobe, outfits, profile

        var title: String {
            switch self {
            case .today:    return "今天"
            case .wardrobe: return "衣橱"
            case .outfits:  return "穿搭"
            case .profile:  return "我的"
            }
        }

        var icon: String {
            switch self {
            case .today:    return "sun.max"
            case .wardrobe: return "tshirt"
            case .outfits:  return "square.on.square"
            case .profile:  return "person"
            }
        }

        var selectedIcon: String {
            switch self {
            case .today:    return "sun.max.fill"
            case .wardrobe: return "tshirt.fill"
            case .outfits:  return "square.on.square.squareshape.controlhandles"
            case .profile:  return "person.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(Tab.today)
                WardrobeView(navigateToItem: $savedItemForDetail)
                    .tag(Tab.wardrobe)
                OutfitsTab()
                    .tag(Tab.outfits)
                ProfileView()
                    .tag(Tab.profile)
            }
            .toolbar(.hidden, for: .tabBar)

            // 半透明遮罩
            if showingAddOptions {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissOptions() }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                // 三个选项按钮（从底部弹出）
                if showingAddOptions {
                    HStack(spacing: 24) {
                        addOptionButton(icon: "camera.fill", title: "拍照", color: .blue) {
                            selectOption { showingAddSheet = true }
                        }
                        addOptionButton(icon: "photo.on.rectangle.angled", title: "相册", color: .green) {
                            selectOption { showingBatchImport = true }
                        }
                        addOptionButton(icon: "cart.fill", title: "淘宝", color: .orange) {
                            selectOption { showingTaobaoImport = true }
                        }
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 自定义 TabBar（始终可见）
                CustomTabBar(
                    selection: $selectedTab,
                    isAddActive: showingAddOptions,
                    onAddTap: toggleOptions
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingAddOptions)
        .sheet(isPresented: $showingAddSheet) {
            AddClothingView(preselectedCategory: nil) { item in
                savedItemForDetail = item
                selectedTab = .wardrobe
            }
        }
        .sheet(isPresented: $showingBatchImport, onDismiss: {
            selectedTab = .wardrobe
        }) {
            BatchImportView(preselectedCategory: nil)
        }
        .sheet(isPresented: $showingTaobaoImport) {
            TaobaoImportView(preselectedCategory: nil)
        }
    }

    // MARK: - Actions

    private func toggleOptions() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingAddOptions.toggle()
        }
    }

    private func dismissOptions() {
        withAnimation(.spring(response: 0.3)) {
            showingAddOptions = false
        }
    }

    /// 选中某个选项：先收起弹窗，等动画结束后再弹 sheet
    private func selectOption(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.3)) {
            showingAddOptions = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            action()
        }
    }

    // MARK: - Option Button

    @ViewBuilder
    private func addOptionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color.gradient)
                    .clipShape(Circle())
                    .shadow(color: color.opacity(0.3), radius: 8, y: 3)
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自定义 TabBar

private struct CustomTabBar: View {
    @Binding var selection: MainTabView.Tab
    var isAddActive: Bool = false
    let onAddTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // 底色 + 模糊背景
            barBackground()
                .frame(height: 54)

            HStack(spacing: 0) {
                tabButton(.today)
                tabButton(.wardrobe)
                addButton()
                tabButton(.outfits)
                tabButton(.profile)
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func barBackground() -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func tabButton(_ tab: MainTabView.Tab) -> some View {
        let isSelected = selection == tab
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func addButton() -> some View {
        Button(action: onAddTap) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isAddActive ? 45 : 0))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .offset(y: -8)
        .accessibilityLabel("添加衣物")
    }
}
