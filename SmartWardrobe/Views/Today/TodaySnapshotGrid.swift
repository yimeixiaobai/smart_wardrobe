import SwiftUI
import SwiftData

/// 数据快照 2x2 网格
/// - 本月穿搭次数
/// - 本月新增数 + 花费
/// - 平均穿着成本
/// - 当季闲置率
struct TodaySnapshotGrid: View {
    let items: [ClothingItem]
    let records: [WearRecord]
    let temperature: Int?

    var body: some View {
        let metrics = IdleAnalysisService.shared.wardrobeMetrics(items: items, temperature: temperature)

        VStack(alignment: .leading, spacing: 10) {
            Text("本月数据")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                SnapshotCell(
                    title: "本月穿搭",
                    value: "\(monthWearCount)",
                    suffix: "次",
                    icon: "calendar.badge.clock",
                    color: .blue
                )
                SnapshotCell(
                    title: "本月新增",
                    value: "\(monthNewCount)",
                    suffix: "件 · ¥\(monthSpent)",
                    icon: "bag.badge.plus",
                    color: .pink
                )
                SnapshotCell(
                    title: "平均穿着成本",
                    value: cpwDisplay(metrics),
                    suffix: "/次",
                    icon: "yensign.circle",
                    color: .orange
                )
                SnapshotCell(
                    title: "当季闲置率",
                    value: "\(Int(metrics.idleRate * 100))",
                    suffix: "%",
                    icon: "zzz",
                    color: idleColor(metrics)
                )
            }
        }
    }

    // MARK: - Metrics

    private var monthWearCount: Int {
        let (start, end) = currentMonthRange()
        return records.filter { $0.date >= start && $0.date < end }.count
    }

    private var monthNewCount: Int {
        let (start, end) = currentMonthRange()
        return items.filter { item in
            let date = item.purchaseDate ?? item.createdAt
            return date >= start && date < end
        }.count
    }

    private var monthSpent: Int {
        let (start, end) = currentMonthRange()
        let total = items
            .filter { item in
                let date = item.purchaseDate ?? item.createdAt
                return date >= start && date < end
            }
            .compactMap(\.purchasePrice)
            .reduce(0, +)
        return Int(total)
    }

    private func cpwDisplay(_ metrics: IdleAnalysisService.WardrobeMetrics) -> String {
        guard let avg = metrics.averageCPW else { return "—" }
        return "¥\(Int(avg))"
    }

    private func idleColor(_ metrics: IdleAnalysisService.WardrobeMetrics) -> Color {
        switch metrics.idleRate {
        case ..<0.2:  return .green
        case ..<0.4:  return .orange
        default:      return .red
        }
    }

    private func currentMonthRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        return (start, end)
    }
}

private struct SnapshotCell: View {
    let title: String
    let value: String
    let suffix: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
