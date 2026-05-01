import SwiftUI
import SwiftData

// MARK: - 目标日（今天 / 明天）

/// Today 首页的目标日
/// - 默认值依当前时间：18:00 后默认"明天"
/// - 用户可手动切换
enum TargetDay: String, Hashable, CaseIterable {
    case today = "今天"
    case tomorrow = "明天"

    /// 根据当前时间推荐默认值：18:00 起切到"明天"
    static var defaultValue: TargetDay {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 ? .tomorrow : .today
    }

    /// 对应的目标日期（用于缓存 key / 季节判断）
    var date: Date {
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: Date())
        case .tomorrow:
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        }
    }

    /// 推荐标题前缀
    var recommendationTitle: String {
        switch self {
        case .today:    return "今日推荐"
        case .tomorrow: return "明日推荐"
        }
    }

    /// 推荐按钮文案
    var ctaText: String {
        switch self {
        case .today:    return "为我推荐今日穿搭"
        case .tomorrow: return "为我推荐明日穿搭"
        }
    }
}

// MARK: - 给子组件展示用的统一天气结构

/// 统一的展示天气结构，屏蔽今日(实时)与明日(预报)差异
struct DisplayWeather {
    let city: String
    let representativeTemp: Int      // 代表温度（展示）
    let condition: String
    /// 仅明日：最低/最高
    let tempRange: (min: Int, max: Int)?
    /// 仅今日：体感
    let feelsLike: Int?
    let humidity: String?

    static func fromToday(_ info: WeatherService.WeatherInfo) -> DisplayWeather {
        DisplayWeather(
            city: info.city,
            representativeTemp: info.temperature,
            condition: info.condition,
            tempRange: nil,
            feelsLike: info.feelsLike,
            humidity: info.humidity
        )
    }

    static func fromTomorrow(_ info: WeatherService.ForecastWeatherInfo) -> DisplayWeather {
        DisplayWeather(
            city: info.city,
            representativeTemp: info.representativeTemp,
            condition: info.conditionDay,
            tempRange: (info.tempMin, info.tempMax),
            feelsLike: nil,
            humidity: info.humidity
        )
    }
}

// MARK: - TodayView

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ClothingItem> { $0.status != "已淘汰" },
           sort: \ClothingItem.createdAt, order: .reverse)
    private var allItems: [ClothingItem]

    @Query(sort: \WearRecord.date, order: .reverse)
    private var wearRecords: [WearRecord]

    @State private var targetDay: TargetDay = .defaultValue
    @State private var todayWeather: WeatherService.WeatherInfo?
    @State private var tomorrowForecast: WeatherService.ForecastWeatherInfo?
    @State private var isLoadingWeather = false
    @State private var weatherError: String?
    @State private var cardsAppeared = false

    /// 根据 targetDay 选择的展示天气
    private var displayWeather: DisplayWeather? {
        switch targetDay {
        case .today:
            return todayWeather.map { DisplayWeather.fromToday($0) }
        case .tomorrow:
            return tomorrowForecast.map { DisplayWeather.fromTomorrow($0) }
        }
    }

    /// 用于闲置分析和推荐的温度（代表值）
    private var effectiveTemperature: Int? {
        displayWeather?.representativeTemp
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    targetDayPicker()

                    TodayWeatherBar(
                        targetDay: targetDay,
                        weather: displayWeather,
                        isLoading: isLoadingWeather,
                        errorMessage: weatherError,
                        onRetry: { Task { await loadWeatherIfNeeded(force: true) } }
                    )
                    .offset(y: cardsAppeared ? 0 : 12)
                    .opacity(cardsAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.05), value: cardsAppeared)

                    TodayRecommendationCard(
                        allItems: allItems,
                        wearRecords: wearRecords,
                        targetDay: targetDay,
                        effectiveTemperature: effectiveTemperature
                    )
                    .offset(y: cardsAppeared ? 0 : 16)
                    .opacity(cardsAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.12), value: cardsAppeared)

                    // 今日打卡卡只在 today 模式下显示
                    if targetDay == .today {
                        TodayCheckinCard(
                            records: wearRecords,
                            allItems: allItems
                        )
                        .offset(y: cardsAppeared ? 0 : 16)
                        .opacity(cardsAppeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: cardsAppeared)
                    }

                    IdleReminderCard(
                        items: allItems,
                        temperature: effectiveTemperature
                    )
                    .offset(y: cardsAppeared ? 0 : 16)
                    .opacity(cardsAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.28), value: cardsAppeared)

                    TodaySnapshotGrid(
                        items: allItems,
                        records: wearRecords,
                        temperature: effectiveTemperature
                    )
                    .offset(y: cardsAppeared ? 0 : 16)
                    .opacity(cardsAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.35), value: cardsAppeared)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(targetDay == .today ? "今天" : "明天")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await loadWeatherIfNeeded()
        }
        .onAppear {
            guard !cardsAppeared else { return }
            cardsAppeared = true
        }
        .onChange(of: targetDay) { _, _ in
            Task { await loadWeatherIfNeeded() }
        }
    }

    // MARK: - Picker

    @ViewBuilder
    private func targetDayPicker() -> some View {
        Picker("", selection: $targetDay) {
            ForEach(TargetDay.allCases, id: \.self) { day in
                Text(day.rawValue).tag(day)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Weather Loading

    private func loadWeatherIfNeeded(force: Bool = false) async {
        guard APIKeyManager.shared.isWeatherConfigured, !isLoadingWeather else { return }

        weatherError = nil

        switch targetDay {
        case .today:
            if !force, let w = todayWeather, Date().timeIntervalSince(w.fetchedAt) < 30 * 60 { return }
            isLoadingWeather = true
            defer { isLoadingWeather = false }
            do {
                todayWeather = try await WeatherService.shared.fetchWeather()
            } catch {
                weatherError = "天气获取失败，点击重试"
            }
        case .tomorrow:
            if !force, let f = tomorrowForecast, Date().timeIntervalSince(f.fetchedAt) < 30 * 60 { return }
            isLoadingWeather = true
            defer { isLoadingWeather = false }
            do {
                tomorrowForecast = try await WeatherService.shared.fetchTomorrowForecast()
            } catch {
                weatherError = "天气预报获取失败，点击重试"
            }
        }
    }
}
