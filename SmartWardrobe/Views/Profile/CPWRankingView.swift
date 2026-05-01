import SwiftUI
import SwiftData

/// CPW 排行榜
/// - 上方：最划算 Top 10（低 CPW，高频穿着）
/// - 下方：最不划算 Top 10（高 CPW，贵而少穿）
struct CPWRankingView: View {
    @Query(filter: #Predicate<ClothingItem> { $0.status != "已淘汰" })
    private var allItems: [ClothingItem]

    @State private var mode: Mode = .best

    enum Mode: String, CaseIterable {
        case best = "最划算"
        case worst = "最不划算"
        case neverWorn = "从未穿过"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            hintText()

            ScrollView {
                LazyVStack(spacing: 8) {
                    let list = rankedItems
                    if list.isEmpty {
                        emptyHint()
                    } else {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            NavigationLink {
                                ClothingDetailView(item: item)
                            } label: {
                                rankRow(index: index + 1, item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("CPW 排行榜")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Ranking

    private var rankedItems: [ClothingItem] {
        switch mode {
        case .best:
            let withCPW = allItems.filter { $0.costPerWear != nil }
            let sorted = withCPW.sorted { a, b in
                let av = a.costPerWear ?? Double.greatestFiniteMagnitude
                let bv = b.costPerWear ?? Double.greatestFiniteMagnitude
                return av < bv
            }
            return Array(sorted.prefix(20))
        case .worst:
            let withCPW = allItems.filter { $0.costPerWear != nil }
            let sorted = withCPW.sorted { a, b in
                let av = a.costPerWear ?? 0
                let bv = b.costPerWear ?? 0
                return av > bv
            }
            return Array(sorted.prefix(20))
        case .neverWorn:
            let never = allItems.filter { $0.wearCount == 0 }
            let sorted = never.sorted { a, b in
                let av = a.purchasePrice ?? 0
                let bv = b.purchasePrice ?? 0
                return av > bv
            }
            return Array(sorted.prefix(20))
        }
    }

    @ViewBuilder
    private func hintText() -> some View {
        let text: String = switch mode {
        case .best:      "每次穿着成本最低的衣物：买得值"
        case .worst:     "每次穿着成本最高的衣物：考虑多穿几次"
        case .neverWorn: "买了还没穿过的衣物，按价格排序"
        }
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func rankRow(index: Int, item: ClothingItem) -> some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 30)
                .foregroundStyle(index <= 3 ? Color.accentColor : .secondary)

            ClothingThumbnailView(item: item)
                .frame(width: 52, height: 60)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let price = item.purchasePrice {
                        Text("¥\(Int(price))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("穿 \(item.wearCount) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let cpw = item.costPerWear {
                    Text("¥\(Int(cpw))")
                        .font(.headline)
                        .foregroundStyle(cpwColor(cpw))
                    Text("/次")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if item.wearCount == 0 {
                    Text("未穿")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cpwColor(_ cpw: Double) -> Color {
        switch cpw {
        case ..<50:   return .green
        case ..<200:  return .primary
        default:      return .red
        }
    }

    @ViewBuilder
    private func emptyHint() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "yensign.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyText: String {
        switch mode {
        case .best, .worst: return "还没有带价格和穿着记录的衣物\n为衣物添加价格后，再穿几次看看"
        case .neverWorn:    return "每件衣物都穿过啦 🎉"
        }
    }
}
