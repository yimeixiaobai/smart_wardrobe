import SwiftUI
import SwiftData

/// 闲置提醒卡（消费 IdleAnalysisService）
/// - 季节首尾 14 天：季节性特殊卡片优先展示
/// - 其余时间：展示最多 3 条常规闲置提醒
/// - 全部为空：展示"衣橱很活跃"的积极空态
struct IdleReminderCard: View {
    let items: [ClothingItem]
    let temperature: Int?

    private var specialReminder: IdleAnalysisService.SpecialReminder {
        IdleAnalysisService.shared.specialReminder(items: items)
    }

    private var reminders: [IdleAnalysisService.IdleEvaluation] {
        IdleAnalysisService.shared.dailyReminders(items: items, temperature: temperature, limit: 3)
    }

    var body: some View {
        // 优先级：季节边界 > 常规闲置 > 空态
        switch specialReminder {
        case .seasonEnding(let season, let items):
            seasonEndingCard(season: season, items: items)
        case .seasonStarting(let season, let items):
            seasonStartingCard(season: season, items: items)
        case .none:
            if items.isEmpty {
                noItemsCard()
            } else if reminders.isEmpty {
                emptyStateCard()
            } else {
                regularCard()
            }
        }
    }

    // MARK: - 常规闲置卡

    @ViewBuilder
    private func regularCard() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("该宠幸的衣服", systemImage: "zzz")
                    .font(.headline)
                Spacer()
                Text("\(reminders.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(reminders, id: \.item.id) { eval in
                    NavigationLink {
                        ClothingDetailView(item: eval.item)
                    } label: {
                        reminderRow(eval)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func reminderRow(_ eval: IdleAnalysisService.IdleEvaluation) -> some View {
        HStack(spacing: 12) {
            ClothingThumbnailView(item: eval.item)
                .frame(width: 56, height: 64)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(eval.item.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(eval.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    statusBadge(eval.status)
                    if let cpw = eval.item.costPerWear {
                        Text("CPW ¥\(Int(cpw))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if eval.item.wearCount == 0 {
                        Text("未穿过")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ status: IdleAnalysisService.IdleStatus) -> some View {
        switch status {
        case .neverWornInSeason:
            TagPill(text: "从未穿过", color: .red)
        case .neverWornAcquiredRecent:
            TagPill(text: "新品待首穿", color: .orange)
        case .idleInSeason:
            TagPill(text: "久未穿着", color: .orange)
        case .highCPWInSeason:
            TagPill(text: "高 CPW", color: .purple)
        default:
            EmptyView()
        }
    }

    // MARK: - 季节末卡片

    @ViewBuilder
    private func seasonEndingCard(season: String, items: [ClothingItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(season)装下架前", systemImage: "sunset")
                    .font(.headline)
                Spacer()
            }

            Text("本季还没穿过这 \(items.count) 件 \(season) 装，抓紧最后的机会")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink {
                            ClothingDetailView(item: item)
                        } label: {
                            thumbTile(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 季节始卡片

    @ViewBuilder
    private func seasonStartingCard(season: String, items: [ClothingItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(season)装登场", systemImage: "leaf")
                    .font(.headline)
                Spacer()
            }

            Text("新季节到了，这些 \(season) 装去年你穿得最少，不妨重新发现")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink {
                            ClothingDetailView(item: item)
                        } label: {
                            thumbTile(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func thumbTile(item: ClothingItem) -> some View {
        VStack(spacing: 4) {
            ClothingThumbnailView(item: item)
                .frame(width: 72, height: 84)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.displayName)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 72)
        }
    }

    // MARK: - 空态

    @ViewBuilder
    private func noItemsCard() -> some View {
        HStack(spacing: 14) {
            Image(systemName: "tshirt")
                .font(.title)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("衣橱还是空的")
                    .font(.subheadline.bold())
                Text("快去添加你的第一件衣物吧")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func emptyStateCard() -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("衣橱很活跃")
                    .font(.subheadline.bold())
                Text("当季衣物都有被好好穿着")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
