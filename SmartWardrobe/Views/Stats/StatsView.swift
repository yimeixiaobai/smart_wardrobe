import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var allItems: [ClothingItem]
    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]
    @Query private var outfits: [Outfit]
    @Query(sort: \WearRecord.date) private var wearRecords: [WearRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                overviewCards()
                wearFrequencyChart()
                topOutfitsChart()
                categoryChart()
                colorChart()
                seasonChart()
            }
            .padding()
        }
        .navigationTitle("衣橱统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func overviewCards() -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "衣物总数", value: "\(allItems.count)", icon: "tshirt", color: .blue)
            StatCard(title: "搭配方案", value: "\(outfits.count)", icon: "square.on.square", color: .purple)
            StatCard(
                title: "收藏衣物",
                value: "\(allItems.filter(\.isFavorite).count)",
                icon: "heart.fill",
                color: .red
            )
            StatCard(
                title: "总价值",
                value: "¥\(totalValue)",
                icon: "yensign.circle",
                color: .orange
            )
        }
    }

    @ViewBuilder
    private func categoryChart() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类分布")
                .font(.headline)

            let data = categoryData
            if data.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(data, id: \.name) { item in
                    SectorMark(
                        angle: .value("数量", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("分类", item.name))
                    .annotation(position: .overlay) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func colorChart() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("颜色分布")
                .font(.headline)

            let data = colorData
            if data.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(data.prefix(8), id: \.name) { item in
                    BarMark(
                        x: .value("颜色", item.name),
                        y: .value("数量", item.count)
                    )
                    .foregroundStyle(Color(hex: item.hex))
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func topOutfitsChart() -> some View {
        // 统计每套搭配被穿的次数
        let outfitWearCounts: [(outfit: Outfit, count: Int)] = outfits.compactMap { outfit in
            let count = wearRecords.filter { $0.outfit?.id == outfit.id }.count
            return count > 0 ? (outfit, count) : nil
        }.sorted { $0.count > $1.count }

        if !outfitWearCounts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("最常穿搭配")
                    .font(.headline)

                ForEach(Array(outfitWearCounts.prefix(5).enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(index < 3 ? Color.accentColor : Color.gray)
                            .clipShape(Circle())

                        Text(item.outfit.name.isEmpty ? "未命名搭配" : item.outfit.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        Text("\(item.count) 次")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func seasonChart() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("季节分布")
                .font(.headline)

            let data = seasonData
            Chart(data, id: \.name) { item in
                BarMark(
                    x: .value("季节", item.name),
                    y: .value("数量", item.count)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 150)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func wearFrequencyChart() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("穿搭频率（近30天）")
                .font(.headline)

            let data = wearFrequencyData
            if data.isEmpty {
                Text("暂无穿搭记录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data, id: \.weekLabel) { item in
                    BarMark(
                        x: .value("周", item.weekLabel),
                        y: .value("次数", item.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var wearFrequencyData: [(weekLabel: String, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: today) else { return [] }

        let recentRecords = wearRecords.filter { $0.date >= thirtyDaysAgo }
        if recentRecords.isEmpty { return [] }

        // Group by week
        var weeks: [(weekLabel: String, count: Int)] = []
        for weekOffset in 0..<5 {
            guard let weekStart = calendar.date(byAdding: .day, value: -((4 - weekOffset) * 7), to: today),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { continue }
            let count = recentRecords.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            let label = ChineseDateFormatter.monthDay(weekStart)
            weeks.append((weekLabel: label, count: count))
        }
        return weeks
    }

    private var totalValue: String {
        let total = allItems.compactMap(\.purchasePrice).reduce(0, +)
        if total == 0 { return "0" }
        return String(format: "%.0f", total)
    }

    private var categoryData: [(name: String, count: Int)] {
        topCategories.map { cat in
            (name: cat.name, count: cat.itemCount)
        }.filter { $0.count > 0 }
    }

    private var colorData: [(name: String, hex: String, count: Int)] {
        var colorCounts: [String: Int] = [:]
        for item in allItems {
            for hex in item.colorHexValues {
                colorCounts[hex, default: 0] += 1
            }
        }
        return colorCounts.map { hex, count in
            let name = AppConstants.PresetColors.all.first { $0.hex == hex }?.name ?? hex
            return (name: name, hex: hex, count: count)
        }.sorted { $0.count > $1.count }
    }

    private var seasonData: [(name: String, count: Int)] {
        AppConstants.Seasons.all.map { season in
            let count = allItems.filter { $0.seasons.contains(season) }.count
            return (name: season, count: count)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            HStack {
                Text(value)
                    .font(.title2.bold())
                Spacer()
            }
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
