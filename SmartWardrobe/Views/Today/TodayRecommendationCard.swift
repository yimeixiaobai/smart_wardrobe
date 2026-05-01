import SwiftUI
import SwiftData

// MARK: - Cached Recommendation (持久化)

/// 按日期持久化的推荐快照（存 UserDefaults）
/// - 只存 item 的 UUID，加载时从当前 allItems 里匹配
/// - 如果匹配不到（衣物被删）则视为过期
private struct CachedRecommendation: Codable {
    let dateKey: String         // yyyy-MM-dd
    let itemIds: [String]       // UUID strings
    let occasion: String
    let reason: String
    let stylingTip: String?

    private static let storageKey = "today_recommendation_cache"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    static func dateKey(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func load(for date: Date) -> CachedRecommendation? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cached = try? JSONDecoder().decode(CachedRecommendation.self, from: data)
        else { return nil }
        guard cached.dateKey == dateKey(for: date) else { return nil }
        return cached
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Today Recommendation Card

/// 今日/明日 AI 推荐主卡
struct TodayRecommendationCard: View {
    @Environment(\.modelContext) private var modelContext

    let allItems: [ClothingItem]
    let wearRecords: [WearRecord]
    let targetDay: TargetDay
    /// 当前 targetDay 对应的温度（用于 UI 展示，真正的 weather context 由 card 内部选取）
    let effectiveTemperature: Int?

    @State private var recommendation: OutfitRecommendationService.OutfitRecommendation?
    @State private var isLoading = false
    @State private var phase: RecommendationPhase = .fetchingWeather
    @State private var errorMessage: String?
    @State private var showingFullRecommendation = false
    @State private var showingSaveSuccess = false
    @State private var showingAPIKeySettings = false
    @State private var elapsedSeconds = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var recommendTask: Task<Void, Never>?

    private let imageService = ImageStorageService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header()

            if !APIKeyManager.shared.isLLMConfigured {
                apiKeyHint()
            } else if allItems.count < 3 {
                emptyHint()
            } else if let rec = recommendation {
                resultView(rec)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let error = errorMessage {
                errorView(error)
            } else {
                callToActionButton()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.accentColor.opacity(0.08), radius: 8, y: 3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingFullRecommendation) {
            NavigationStack {
                RecommendationView()
            }
        }
        .sheet(isPresented: $showingAPIKeySettings) {
            NavigationStack {
                APIKeySettingsView()
            }
        }
        .alert("已保存到搭配列表", isPresented: $showingSaveSuccess) {
            Button("好的") {}
        }
        .onAppear {
            restoreCachedRecommendationIfAvailable()
        }
        .onDisappear {
            recommendTask?.cancel()
            recommendTask = nil
            timerTask?.cancel()
            timerTask = nil
        }
        .onChange(of: targetDay) { _, _ in
            // 切换 today/tomorrow 时，重置展示并尝试恢复该日期的缓存
            recommendation = nil
            errorMessage = nil
            restoreCachedRecommendationIfAvailable()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func header() -> some View {
        HStack {
            Label(targetDay.recommendationTitle, systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if recommendation != nil {
                Button {
                    recommendTask = Task { await loadRecommendation() }
                } label: {
                    Label("换一套", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder
    private func apiKeyHint() -> some View {
        VStack(spacing: 14) {
            // 功能说明
            HStack(spacing: 12) {
                featurePoint(icon: "cloud.sun.fill", color: .blue, text: "结合天气推荐穿搭")
                featurePoint(icon: "tshirt.fill", color: .orange, text: "基于你的衣橱搭配")
            }

            // 配置进度
            let step = configStep
            HStack(spacing: 6) {
                stepDot(index: 1, current: step, label: "配置 AI")
                stepLine(done: step > 1)
                stepDot(index: 2, current: step, label: "添加衣物")
                stepLine(done: step > 2)
                stepDot(index: 3, current: step, label: "获取推荐")
            }
            .padding(.vertical, 4)

            Button {
                showingAPIKeySettings = true
            } label: {
                Label("前往配置", systemImage: "gearshape")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyHint() -> some View {
        VStack(spacing: 10) {
            // 配置进度
            let step = configStep
            HStack(spacing: 6) {
                stepDot(index: 1, current: step, label: "配置 AI")
                stepLine(done: step > 1)
                stepDot(index: 2, current: step, label: "添加衣物")
                stepLine(done: step > 2)
                stepDot(index: 3, current: step, label: "获取推荐")
            }

            Text("再添加 \(max(0, 3 - allItems.count)) 件衣物即可开始推荐")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    /// 当前配置进度：1=未配置AI, 2=已配置AI但衣物不足, 3=就绪
    private var configStep: Int {
        if !APIKeyManager.shared.isLLMConfigured { return 1 }
        if allItems.count < 3 { return 2 }
        return 3
    }

    @ViewBuilder
    private func featurePoint(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stepDot(index: Int, current: Int, label: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(index < current ? Color.green : (index == current ? Color.accentColor : Color(.systemGray4)))
                    .frame(width: 22, height: 22)
                if index < current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(index == current ? .white : .secondary)
                }
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(index <= current ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func stepLine(done: Bool) -> some View {
        Rectangle()
            .fill(done ? Color.green : Color(.systemGray4))
            .frame(height: 2)
            .frame(maxWidth: 30)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private func callToActionButton() -> some View {
        VStack(spacing: 12) {
            Button {
                recommendTask = Task { await loadRecommendation() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                        Text(phaseText()).foregroundStyle(.white)
                        Spacer()
                        Text("\(elapsedSeconds)s")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Image(systemName: "sparkles")
                        Text(targetDay.ctaText).fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    LinearGradient(
                        colors: isLoading
                            ? [Color.gray, Color.gray.opacity(0.8)]
                            : [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)

            if isLoading {
                LoadingTipsView()
            }
        }
    }

    @ViewBuilder
    private func resultView(_ rec: OutfitRecommendationService.OutfitRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 缩略图横排
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rec.items, id: \.id) { item in
                        ClothingThumbnailView(item: item)
                            .frame(width: 88, height: 100)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TagPill(text: rec.occasion, color: .blue)
                    Spacer()
                }
                Text(rec.reason)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let tip = rec.stylingTip, !tip.isEmpty {
                    Text("💡 \(tip)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    saveAsOutfit(rec)
                } label: {
                    Label("加入穿搭", systemImage: "square.on.square")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingFullRecommendation = true
                } label: {
                    Label("更多方案", systemImage: "arrow.forward")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                recommendTask = Task { await loadRecommendation() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Persistence

    /// 从缓存恢复当前 targetDay 的推荐（如果有）
    /// 要求所有缓存的衣物都仍存在，否则视为过期（衣物被删后推荐文案可能不准确）
    private func restoreCachedRecommendationIfAvailable() {
        guard recommendation == nil,
              let cached = CachedRecommendation.load(for: targetDay.date)
        else { return }

        // 按 UUID 匹配回 allItems
        let matched = cached.itemIds.compactMap { idStr -> ClothingItem? in
            guard let uuid = UUID(uuidString: idStr) else { return nil }
            return allItems.first { $0.id == uuid }
        }

        // 所有缓存衣物必须仍存在，否则丢弃缓存
        guard matched.count == cached.itemIds.count, matched.count >= 2 else {
            CachedRecommendation.clear()
            return
        }

        recommendation = OutfitRecommendationService.OutfitRecommendation(
            items: matched,
            occasion: cached.occasion,
            reason: cached.reason,
            stylingTip: cached.stylingTip,
            unmatchedIds: []
        )
    }

    private func persistRecommendation(_ rec: OutfitRecommendationService.OutfitRecommendation) {
        let cached = CachedRecommendation(
            dateKey: CachedRecommendation.dateKey(for: targetDay.date),
            itemIds: rec.items.map { $0.id.uuidString },
            occasion: rec.occasion,
            reason: rec.reason,
            stylingTip: rec.stylingTip
        )
        cached.save()
    }

    // MARK: - Actions

    private func loadRecommendation() async {
        isLoading = true
        errorMessage = nil
        phase = .fetchingWeather
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
            // 构造目标日的 weather context
            let override = await buildWeatherOverride()

            let result = try await OutfitRecommendationService.shared.recommendToday(
                items: allItems,
                wearRecords: wearRecords,
                occasion: "日常",
                overrideWeather: override,
                contextLabel: targetDay == .tomorrow ? "明天" : "今天",
                onPhaseChange: { @Sendable p in
                    await MainActor.run { self.phase = p }
                }
            )
            withAnimation(.easeOut(duration: 0.35)) {
                recommendation = result.recommendations.first
            }
            if let first = recommendation {
                persistRecommendation(first)
            } else {
                errorMessage = "暂未能生成推荐，稍后再试"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        timerTask?.cancel()
        timerTask = nil
        isLoading = false
    }

    /// 根据 targetDay 构造 WeatherInfo override
    /// - today: 返回 nil（让 service 自己 fetch 实时）
    /// - tomorrow: fetch 3d 预报并转换为 WeatherInfo
    private func buildWeatherOverride() async -> WeatherService.WeatherInfo? {
        switch targetDay {
        case .today:
            return nil
        case .tomorrow:
            guard APIKeyManager.shared.isWeatherConfigured else { return nil }
            do {
                let forecast = try await WeatherService.shared.fetchTomorrowForecast()
                return WeatherService.WeatherInfo(
                    temperature: forecast.representativeTemp,
                    condition: forecast.conditionDay,
                    city: forecast.city,
                    feelsLike: forecast.tempMax,  // 白天体感约等于最高温
                    humidity: forecast.humidity,
                    fetchedAt: forecast.fetchedAt
                )
            } catch {
                // 明日预报不可用时静默降级，不影响推荐流程
                return nil
            }
        }
    }

    private func saveAsOutfit(_ rec: OutfitRecommendationService.OutfitRecommendation) {
        if Outfit.createFromRecommendation(name: "AI推荐·\(rec.occasion)", recommendation: rec, in: modelContext) != nil {
            showingSaveSuccess = true
        }
    }

    private func phaseText() -> String {
        switch phase {
        case .fetchingWeather:   return "读取天气..."
        case .analyzingWardrobe: return "分析衣橱..."
        case .generatingOutfit:  return "生成方案..."
        case .parsingResult:     return "整理结果..."
        }
    }
}
