import SwiftUI
import SwiftData

struct RecommendationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<ClothingItem> { $0.status != "已淘汰" },
           sort: \ClothingItem.createdAt, order: .reverse)
    private var activeItems: [ClothingItem]
    @Query(sort: \WearRecord.date, order: .reverse) private var wearRecords: [WearRecord]

    @State private var selectedOccasion = "日常"
    @State private var result: OutfitRecommendationService.RecommendationResult?
    @State private var isLoading = false
    @State private var recommendPhase: RecommendationPhase = .fetchingWeather
    @State private var errorMessage: String?
    @State private var showingSaveSuccess = false
    @State private var showingAPIKeySettings = false
    @State private var elapsedSeconds = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var recommendTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !APIKeyManager.shared.isLLMConfigured {
                    apiKeyHint()
                } else {
                    weatherCard()
                    occasionSelector()
                    recommendButton()
                    resultContent()
                }
            }
            .padding()
        }
        .navigationTitle("智能推荐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(isPresented: $showingAPIKeySettings) {
            NavigationStack {
                APIKeySettingsView()
            }
        }
        .alert("已保存", isPresented: $showingSaveSuccess) {
            Button("好的") {}
        } message: {
            Text("搭配方案已保存到搭配列表")
        }
        .onDisappear {
            recommendTask?.cancel()
            recommendTask = nil
            timerTask?.cancel()
            timerTask = nil
        }
    }

    // MARK: - API Key Hint

    @ViewBuilder
    private func apiKeyHint() -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.opacity(0.5))

            Text("智能穿搭推荐")
                .font(.title3.bold())

            // 功能亮点
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "cloud.sun.fill", color: .blue, text: "根据实时天气和温度推荐穿搭")
                featureRow(icon: "figure.stand", color: .orange, text: "分析你的衣橱自动搭配方案")
                featureRow(icon: "arrow.triangle.2.circlepath", color: .green, text: "智能避开近期穿过的衣物")
            }
            .padding(.horizontal, 8)

            Button {
                showingAPIKeySettings = true
            } label: {
                Label("前往配置", systemImage: "gearshape")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)

            Text("需要先完成 AI 设置")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 20)
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Weather Card

    @ViewBuilder
    private func weatherCard() -> some View {
        if let weather = result?.weather {
            HStack(spacing: 12) {
                Image(systemName: weatherIcon(weather.condition))
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.city)
                        .font(.subheadline.bold())
                    Text("\(weather.temperature)°C · \(weather.condition)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("体感 \(weather.feelsLike)°C")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("湿度 \(weather.humidity)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if !APIKeyManager.shared.isWeatherConfigured {
            HStack {
                Image(systemName: "cloud.sun")
                    .foregroundStyle(.secondary)
                Text("配置天气服务后可结合天气推荐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Occasion

    @ViewBuilder
    private func occasionSelector() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择场合")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppConstants.Occasion.all, id: \.self) { occ in
                        let isSelected = selectedOccasion == occ
                        Button {
                            selectedOccasion = occ
                        } label: {
                            Text(occ)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Recommend Button

    @ViewBuilder
    private func recommendButton() -> some View {
        VStack(spacing: 0) {
            Button {
                recommendTask = Task { await fetchRecommendations() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                        Text("正在分析...")
                        Spacer()
                        Text("\(elapsedSeconds)s")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Image(systemName: "sparkles")
                        Text("为我推荐")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(isLoading ? Color.gray : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading || activeItems.count < 3)

            if isLoading {
                RecommendationProgressView(phase: recommendPhase)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func resultContent() -> some View {
        if isLoading {
            loadingPlaceholder()
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    recommendTask = Task { await fetchRecommendations() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 20)
        } else if let result, !result.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("推荐方案")
                    .font(.headline)

                ForEach(Array(result.recommendations.enumerated()), id: \.element.id) { index, rec in
                    RecommendationCardView(recommendation: rec) {
                        saveAsOutfit(rec)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.08), value: result.recommendations.count)
                }
            }
        } else if result != nil {
            VStack(spacing: 8) {
                Image(systemName: "tshirt")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("未能生成推荐，请稍后重试")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        } else if activeItems.count < 3 {
            VStack(spacing: 8) {
                Image(systemName: "tshirt")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("请先添加至少 3 件衣物")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
        }
    }

    // MARK: - Loading Placeholder

    @ViewBuilder
    private func loadingPlaceholder() -> some View {
        VStack(spacing: 16) {
            // 骨架屏卡片
            ForEach(0..<2, id: \.self) { _ in
                skeletonCard()
            }

            // 穿搭小贴士
            LoadingTipsView()
        }
    }

    @ViewBuilder
    private func skeletonCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 模拟缩略图行
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 70, height: 70)
                }
            }
            // 模拟文字行
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 14)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 14)
                .frame(width: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shimmer()
    }

    // MARK: - Actions

    private func fetchRecommendations() async {
        isLoading = true
        recommendPhase = .fetchingWeather
        errorMessage = nil
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }

        do {
            result = try await OutfitRecommendationService.shared.recommendToday(
                items: activeItems,
                wearRecords: wearRecords,
                occasion: selectedOccasion,
                onPhaseChange: { @Sendable phase in
                    await MainActor.run {
                        self.recommendPhase = phase
                    }
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        timerTask?.cancel()
        timerTask = nil
        isLoading = false
    }

    private func saveAsOutfit(_ rec: OutfitRecommendationService.OutfitRecommendation) {
        if Outfit.createFromRecommendation(name: "AI推荐·\(rec.occasion)", recommendation: rec, in: modelContext) != nil {
            showingSaveSuccess = true
        }
    }

    private func weatherIcon(_ condition: String) -> String {
        if condition.contains("晴") { return "sun.max.fill" }
        if condition.contains("云") { return "cloud.fill" }
        if condition.contains("雨") { return "cloud.rain.fill" }
        if condition.contains("雪") { return "cloud.snow.fill" }
        if condition.contains("雾") { return "cloud.fog.fill" }
        if condition.contains("风") { return "wind" }
        return "cloud.sun.fill"
    }
}
