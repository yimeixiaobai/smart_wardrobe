import SwiftUI

/// 合并「搭配方案」和「穿搭日历」的容器 Tab
/// - 顶部 segmented control 切换
/// - 内嵌的子视图不带自己的 NavigationStack，由本容器提供
struct OutfitsTab: View {
    @State private var mode: Mode = .outfits

    enum Mode: String, Hashable, CaseIterable {
        case outfits = "搭配方案"
        case calendar = "穿搭日历"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    switch mode {
                    case .outfits:  OutfitListView()
                    case .calendar: CalendarView()
                    }
                }
            }
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
