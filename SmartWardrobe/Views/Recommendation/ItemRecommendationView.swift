import SwiftUI
import SwiftData

struct ItemRecommendationView: View {
    let item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]
    @Query(sort: \WearRecord.date, order: .reverse) private var wearRecords: [WearRecord]

    @State private var recommendations: [OutfitRecommendationService.OutfitRecommendation] = []
    @State private var isLoading = false
    @State private var recommendPhase: ItemRecommendationPhase = .analyzingItem
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var showingSaveSuccess = false
    @State private var showingAPIKeySettings = false
    @State private var recommendTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            if !APIKeyManager.shared.isLLMConfigured {
                apiNotConfiguredView()
            } else if isLoading {
                loadingView()
            } else if let error = errorMessage {
                errorView(error)
            } else if recommendations.isEmpty && hasLoaded {
                emptyView()
            } else if !recommendations.isEmpty {
                recommendationsList()
            } else {
                promptView()
            }
        }
        .padding(.top, 12)
        .onDisappear {
            recommendTask?.cancel()
            recommendTask = nil
        }
    }

    // MARK: - States

    @ViewBuilder
    private func apiNotConfiguredView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(Color.accentColor.opacity(0.6))

            Text("AI 搭配建议")
                .font(.subheadline.bold())

            Text("完成 AI 设置后，可根据这件衣物的颜色和风格自动推荐搭配方案")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                showingAPIKeySettings = true
            } label: {
                Label("前往配置", systemImage: "gearshape")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 30)
        .sheet(isPresented: $showingAPIKeySettings) {
            NavigationStack {
                APIKeySettingsView()
            }
        }
    }

    @ViewBuilder
    private func loadingView() -> some View {
        RecommendationProgressView(phase: recommendPhase)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                recommendTask = Task { await fetchRecommendations() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private func emptyView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("未能生成推荐，请稍后重试")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func promptView() -> some View {
        VStack(spacing: 12) {
            Text("这件配什么好看？")
                .font(.subheadline.bold())

            Button {
                recommendTask = Task { await fetchRecommendations() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("获取搭配建议")
                }
                .font(.subheadline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }

            if allItems.count < 5 {
                Text("衣物较少，推荐效果可能有限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private func recommendationsList() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搭配建议")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    recommendTask = Task { await fetchRecommendations() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("换一批")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)

            ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, rec in
                RecommendationCardView(recommendation: rec) {
                    saveAsOutfit(rec)
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.08), value: recommendations.count)
            }
        }
        .alert("已保存", isPresented: $showingSaveSuccess) {
            Button("好的") {}
        } message: {
            Text("搭配方案已保存到搭配列表")
        }
    }

    // MARK: - Actions

    private func fetchRecommendations() async {
        isLoading = true
        recommendPhase = .analyzingItem
        errorMessage = nil

        do {
            recommendations = try await OutfitRecommendationService.shared.recommendForItem(
                targetItem: item,
                allItems: allItems,
                wearRecords: wearRecords,
                onPhaseChange: { @Sendable phase in
                    await MainActor.run {
                        self.recommendPhase = phase
                    }
                }
            )
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveAsOutfit(_ rec: OutfitRecommendationService.OutfitRecommendation) {
        if Outfit.createFromRecommendation(name: "AI推荐·\(item.displayName)", recommendation: rec, in: modelContext) != nil {
            showingSaveSuccess = true
        }
    }
}
