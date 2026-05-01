import SwiftUI

struct APIKeySettingsView: View {
    @AppStorage("llm_base_url") private var llmBaseURL = ""
    @AppStorage("llm_model") private var llmModel = ""
    @State private var llmKey: String = APIKeyManager.shared.llmAPIKey ?? ""
    @State private var showLLMKey = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    @State private var weatherKey: String = APIKeyManager.shared.qWeatherAPIKey ?? ""
    @State private var weatherHost: String = APIKeyManager.shared.qWeatherAPIHost ?? ""
    @State private var showWeatherKey = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("接口地址")
                        .font(.subheadline.bold())
                    TextField("", text: $llmBaseURL, prompt: Text("https://api.example.com/v1/chat/completions").foregroundStyle(.quaternary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.caption, design: .monospaced))
                    Text("服务商提供的完整接口地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("模型名称")
                        .font(.subheadline.bold())
                    TextField("", text: $llmModel, prompt: Text("gpt-4o / claude-sonnet-4-20250514").foregroundStyle(.quaternary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.caption, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("密钥")
                            .font(.subheadline.bold())
                        Spacer()
                        statusDot(configured: !llmKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        if showLLMKey {
                            TextField("", text: $llmKey, prompt: Text("sk-...").foregroundStyle(.quaternary))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $llmKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        Button {
                            showLLMKey.toggle()
                        } label: {
                            Image(systemName: showLLMKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: llmKey) { _, newValue in
                        APIKeyManager.shared.llmAPIKey = newValue.isEmpty ? nil : newValue
                    }
                }
            } header: {
                Text("模型配置")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "测试中..." : "测试连接")
                    }
                }
                .disabled(isTesting || llmKey.trimmingCharacters(in: .whitespaces).isEmpty)

                if let testResult {
                    HStack {
                        Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSuccess ? .green : .red)
                        Text(testResult)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(.subheadline.bold())
                        Spacer()
                        statusDot(configured: !weatherKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        if showWeatherKey {
                            TextField("", text: $weatherKey, prompt: Text("和风天气 API Key").foregroundStyle(.quaternary))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                        } else {
                            SecureField("和风天气 API Key", text: $weatherKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        Button {
                            showWeatherKey.toggle()
                        } label: {
                            Image(systemName: showWeatherKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: weatherKey) { _, newValue in
                        APIKeyManager.shared.qWeatherAPIKey = newValue.isEmpty ? nil : newValue
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("接口地址")
                        .font(.subheadline.bold())
                    TextField("", text: $weatherHost, prompt: Text("选填，默认使用免费开发版").foregroundStyle(.quaternary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.caption, design: .monospaced))
                    Text("商业版用户填写专属域名，免费版留空即可")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: weatherHost) { _, newValue in
                    APIKeyManager.shared.qWeatherAPIHost = newValue.isEmpty ? nil : newValue
                }
            } header: {
                Text("天气服务（和风天气）")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("使用说明", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("1. 填写模型配置后即可使用 AI 搭配推荐与衣物智能识别")
                        .font(.caption)
                    Text("2. 模型需要支持图片识别能力")
                        .font(.caption)
                    Text("3. 填写天气 API Key 后可获取天气数据辅助推荐")
                        .font(.caption)
                    Text("4. 所有配置仅存储在本地设备上")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                llmKey = APIKeyManager.shared.llmAPIKey ?? ""
                weatherKey = APIKeyManager.shared.qWeatherAPIKey ?? ""
                weatherHost = APIKeyManager.shared.qWeatherAPIHost ?? ""
            }
        }
    }

    @ViewBuilder
    private func statusDot(configured: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(configured ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(configured ? "已配置" : "未配置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        do {
            let messages: [LLMService.ChatMessage] = [
                .init(role: "user", content: "请直接输出：你好")
            ]
            _ = try await LLMService.shared.chat(
                messages: messages,
                jsonMode: false
            )
            testResult = "AI 服务连接成功"
            testSuccess = true
        } catch {
            testResult = error.localizedDescription
            testSuccess = false
        }

        isTesting = false
    }
}
