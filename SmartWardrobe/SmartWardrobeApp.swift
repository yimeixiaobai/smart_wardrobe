import SwiftUI
import SwiftData
import os

@main
struct SmartWardrobeApp: App {
    private static let logger = Logger(subsystem: "com.smartwardrobe", category: "App")

    let container: ModelContainer?
    let initError: String?

    @State private var showResetConfirmation = false

    init() {
        let schema = Schema([
            Category.self, ClothingItem.self,
            Outfit.self, OutfitSlot.self,
            WearRecord.self, WearRecordItem.self
        ], version: Schema.Version(1, 0, 0))
        let config = ModelConfiguration()
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            initError = nil
        } catch {
            Self.logger.error("数据库初始化失败: \(error.localizedDescription)")
            container = nil
            initError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    .modelContainer(container)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("数据库初始化失败")
                        .font(.title3.bold())
                    Text(initError ?? "未知错误")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("请尝试重启应用，如仍无法恢复可重置数据库")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重置数据库", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .alert("确认重置？", isPresented: $showResetConfirmation) {
                    Button("取消", role: .cancel) {}
                    Button("重置", role: .destructive) {
                        Self.deleteStoreFiles()
                        // 提示用户重启
                        Self.logger.warning("用户手动重置数据库，需要重启应用")
                    }
                } message: {
                    Text("此操作将删除所有衣物、搭配和穿搭记录数据，且无法恢复。重置后请重启应用。")
                }
            }
        }
    }

    private static func deleteStoreFiles() {
        let fm = FileManager.default
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(filePath: storeURL.path + suffix)
            try? fm.removeItem(at: url)
        }
    }
}
