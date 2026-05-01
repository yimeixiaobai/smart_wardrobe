import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL?
    @State private var shareItem: ShareItem?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertIsError = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await performExport() }
                } label: {
                    HStack {
                        Label("导出数据", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting || isImporting)
            } footer: {
                Text("将所有衣物、搭配、穿搭记录和图片打包为 ZIP 文件，可通过 AirDrop、微信等方式分享")
            }

            Section {
                Button {
                    showFileImporter = true
                } label: {
                    HStack {
                        Label("导入数据", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting || isImporting)
            } footer: {
                Text("从备份文件恢复数据，导入会覆盖当前所有数据")
            }
        }
        .navigationTitle("数据导入/导出")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    pendingImportURL = url
                    showImportConfirm = true
                }
            case .failure(let error):
                showError(error.localizedDescription)
            }
        }
        .alert("确认导入", isPresented: $showImportConfirm) {
            Button("取消", role: .cancel) {
                pendingImportURL = nil
            }
            Button("覆盖导入", role: .destructive) {
                if let url = pendingImportURL {
                    Task { await performImport(from: url) }
                }
            }
        } message: {
            Text("导入将覆盖当前所有数据（衣物、搭配、穿搭记录和图片），此操作不可撤销。建议先导出备份。")
        }
        .alert(alertIsError ? "错误" : "完成", isPresented: $showAlert) {
            Button("好的") {}
        } message: {
            if let msg = alertMessage {
                Text(msg)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(url: item.url)
        }
    }

    private func performExport() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await WardrobeDataService.shared.exportData(context: modelContext)
            shareItem = ShareItem(url: url)
        } catch {
            showError("导出失败：\(error.localizedDescription)")
        }
    }

    private func performImport(from url: URL) async {
        isImporting = true
        defer {
            isImporting = false
            pendingImportURL = nil
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            try await WardrobeDataService.shared.importData(from: url, context: modelContext)
            showSuccess("导入成功，数据已恢复")
        } catch {
            showError("导入失败：\(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        alertIsError = true
        showAlert = true
    }

    private func showSuccess(_ message: String) {
        alertMessage = message
        alertIsError = false
        showAlert = true
    }
}

// MARK: - Share Item

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - UIActivityViewController Wrapper

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
