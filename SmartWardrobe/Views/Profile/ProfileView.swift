import SwiftUI
import SwiftData

/// 「我的」Tab：统计 + 设置 + 衣橱洞察汇聚
struct ProfileView: View {
    @Query(filter: #Predicate<ClothingItem> { $0.status != "已淘汰" })
    private var allItems: [ClothingItem]

    @State private var storageSizeText: String = "计算中…"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("统计") {
                    NavigationLink {
                        StatsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.pie")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("衣橱统计")
                        }
                    }
                    NavigationLink {
                        CPWRankingView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("性价比排行")
                        }
                    }
                }

                Section("衣橱管理") {
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("分类管理")
                        }
                    }
                    NavigationLink {
                        RetiredItemsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.brown)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("已淘汰衣物")
                        }
                    }
                }

                Section("设置") {
                    NavigationLink {
                        APIKeySettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("AI 设置")
                            Spacer()
                            if APIKeyManager.shared.isLLMConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Text("未配置")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink {
                        MannequinSetupView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.stand")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.pink)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("模特照片")
                        }
                    }
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text("数据导入/导出")
                        }
                    }
                }

                Section {
                    HStack {
                        Label("存储占用", systemImage: "internaldrive")
                        Spacer()
                        Text(storageSizeText)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text("智能衣橱 v1.0.0")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle("我的")
            .task {
                storageSizeText = await calculateStorageSize()
            }
        }
    }

    @ViewBuilder
    private func headerCard() -> some View {
        let totalValue = allItems.compactMap(\.purchasePrice).reduce(0, +)
        let cpws = allItems.compactMap(\.costPerWear)
        let avgCPW = cpws.isEmpty ? nil : cpws.reduce(0, +) / Double(cpws.count)

        VStack(spacing: 16) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的衣橱")
                        .font(.title3.bold())
                    Text("已收纳")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    + Text(" \(allItems.count) ")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(Color.accentColor)
                    + Text("件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                HeaderMetric(
                    label: "总价值",
                    value: "¥\(Int(totalValue))",
                    icon: "yensign.circle",
                    color: .orange
                )
                HeaderMetric(
                    label: "单次穿着成本",
                    value: avgCPW.map { "¥\(Int($0))" } ?? "—",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue
                )
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), Color(.systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// 在后台线程计算存储大小，避免阻塞主线程
    private func calculateStorageSize() async -> String {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let imagesDir = docs.appendingPathComponent("ClothingImages")
            let thumbsDir = docs.appendingPathComponent("Thumbnails")

            var total: UInt64 = 0
            for dir in [imagesDir, thumbsDir] {
                if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                    for file in files {
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                        total += UInt64(size)
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useKB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(total))
        }.value
    }
}

private struct HeaderMetric: View {
    let label: String
    let value: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
