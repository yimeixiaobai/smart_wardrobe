import Foundation
import CoreLocation

actor WeatherService {
    static let shared = WeatherService()

    // MARK: - Types

    struct WeatherInfo {
        let temperature: Int
        let condition: String
        let city: String
        let feelsLike: Int
        let humidity: String
        let fetchedAt: Date
    }

    /// 未来某日的天气预报（用于"明日推荐"）
    struct ForecastWeatherInfo {
        let date: Date              // 预报对应日期
        let tempMax: Int
        let tempMin: Int
        let conditionDay: String    // 白天天气
        let conditionNight: String  // 夜间天气
        let humidity: String
        let city: String
        let fetchedAt: Date

        /// 代表温度（中位），用于送给 LLM 做推荐
        var representativeTemp: Int { (tempMax + tempMin) / 2 }
    }

    enum WeatherError: LocalizedError {
        case noAPIKey
        case locationUnavailable
        case networkError(String)
        case apiError(String)
        case decodingError
        case timeout

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "未配置和风天气 API Key，请在设置中添加"
            case .locationUnavailable: return "无法获取位置信息，请检查定位权限"
            case .networkError(let msg): return "网络错误：\(msg)"
            case .apiError(let msg): return "天气 API 错误：\(msg)"
            case .decodingError: return "天气数据解析失败"
            case .timeout: return "天气请求超时"
            }
        }
    }

    // QWeather API response
    private struct QWeatherResponse: Codable {
        let code: String
        let now: NowWeather?
    }

    private struct NowWeather: Codable {
        let temp: String
        let feelsLike: String
        let text: String
        let humidity: String
    }

    // 3 日预报响应
    private struct QWeatherForecastResponse: Codable {
        let code: String
        let daily: [DailyWeather]?
    }

    private struct DailyWeather: Codable {
        let fxDate: String      // yyyy-MM-dd
        let tempMax: String
        let tempMin: String
        let textDay: String
        let textNight: String
        let humidity: String
    }

    private struct GeoResponse: Codable {
        let code: String
        let location: [GeoLocation]?
    }

    private struct GeoLocation: Codable {
        let name: String
        let adm1: String
    }

    // MARK: - Cache

    private var cachedWeather: WeatherInfo?
    private var cachedForecast: ForecastWeatherInfo?

    var currentWeather: WeatherInfo? {
        guard let cached = cachedWeather,
              Date().timeIntervalSince(cached.fetchedAt) < AppConstants.API.weatherCacheDuration else {
            return nil
        }
        return cached
    }

    /// 明日预报缓存（有效期同 weatherCacheDuration）
    var currentForecast: ForecastWeatherInfo? {
        guard let cached = cachedForecast,
              Date().timeIntervalSince(cached.fetchedAt) < AppConstants.API.weatherCacheDuration,
              Calendar.current.isDateInTomorrow(cached.date)
        else {
            return nil
        }
        return cached
    }

    // MARK: - Timeout URLSession

    /// 专用 URLSession，超时 10 秒，避免默认 60 秒卡死
    private nonisolated let shortTimeoutSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    func fetchWeather() async throws -> WeatherInfo {
        // Return cached if still valid
        if let cached = currentWeather {
            return cached
        }

        guard let apiKey = APIKeyManager.shared.qWeatherAPIKey,
              !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WeatherError.noAPIKey
        }

        // 定位：10 秒超时
        let location = try await withTimeout(seconds: 10) {
            try await self.getCurrentLocation()
        }

        let lon = String(format: "%.2f", location.coordinate.longitude)
        let lat = String(format: "%.2f", location.coordinate.latitude)
        let locationStr = "\(lon),\(lat)"

        // Fetch weather and city name in parallel, each with short timeout
        async let weatherData = fetchWeatherData(location: locationStr, apiKey: apiKey)
        async let cityName = fetchCityName(location: locationStr, apiKey: apiKey)

        let weather = try await weatherData
        let city = await cityName

        let info = WeatherInfo(
            temperature: Int(weather.temp) ?? 0,
            condition: weather.text,
            city: city,
            feelsLike: Int(weather.feelsLike) ?? 0,
            humidity: weather.humidity,
            fetchedAt: Date()
        )

        cachedWeather = info
        return info
    }

    /// 获取明日天气预报
    func fetchTomorrowForecast() async throws -> ForecastWeatherInfo {
        if let cached = currentForecast {
            return cached
        }

        guard let apiKey = APIKeyManager.shared.qWeatherAPIKey,
              !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WeatherError.noAPIKey
        }

        let location = try await withTimeout(seconds: 10) {
            try await self.getCurrentLocation()
        }
        let lon = String(format: "%.2f", location.coordinate.longitude)
        let lat = String(format: "%.2f", location.coordinate.latitude)
        let locationStr = "\(lon),\(lat)"

        async let forecastData = fetchForecastData(location: locationStr, apiKey: apiKey)
        async let cityName = fetchCityName(location: locationStr, apiKey: apiKey)

        let daily = try await forecastData
        let city = await cityName

        // daily[0] 是今天，daily[1] 是明天
        guard daily.count >= 2 else {
            throw WeatherError.apiError("预报数据不足")
        }
        let tomorrow = daily[1]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let date = formatter.date(from: tomorrow.fxDate) ?? Date().addingTimeInterval(86400)

        let info = ForecastWeatherInfo(
            date: date,
            tempMax: Int(tomorrow.tempMax) ?? 0,
            tempMin: Int(tomorrow.tempMin) ?? 0,
            conditionDay: tomorrow.textDay,
            conditionNight: tomorrow.textNight,
            humidity: tomorrow.humidity,
            city: city,
            fetchedAt: Date()
        )

        cachedForecast = info
        return info
    }

    nonisolated func currentSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return "春"
        case 6...8: return "夏"
        case 9...11: return "秋"
        default: return "冬"
        }
    }

    // MARK: - Private

    private func buildURL(base: String, location: String, apiKey: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "location", value: location))
        items.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = items
        return components.url
    }

    private func fetchWeatherData(location: String, apiKey: String) async throws -> NowWeather {
        guard let url = buildURL(base: APIKeyManager.shared.qWeatherBaseURL, location: location, apiKey: apiKey) else {
            throw WeatherError.networkError("无效 URL")
        }

        let (data, _) = try await shortTimeoutSession.data(from: url)
        let response = try JSONDecoder().decode(QWeatherResponse.self, from: data)

        guard response.code == "200", let now = response.now else {
            throw WeatherError.apiError("状态码: \(response.code)")
        }

        return now
    }

    private func fetchForecastData(location: String, apiKey: String) async throws -> [DailyWeather] {
        guard let url = buildURL(base: APIKeyManager.shared.qWeatherForecastURL, location: location, apiKey: apiKey) else {
            throw WeatherError.networkError("无效 URL")
        }

        let (data, _) = try await shortTimeoutSession.data(from: url)
        let response = try JSONDecoder().decode(QWeatherForecastResponse.self, from: data)

        guard response.code == "200", let daily = response.daily else {
            throw WeatherError.apiError("状态码: \(response.code)")
        }

        return daily
    }

    private func fetchCityName(location: String, apiKey: String) async -> String {
        guard let url = buildURL(base: APIKeyManager.shared.qWeatherGeoURL, location: location, apiKey: apiKey) else { return "未知" }

        do {
            let (data, _) = try await shortTimeoutSession.data(from: url)
            let response = try JSONDecoder().decode(GeoResponse.self, from: data)
            if let loc = response.location?.first {
                return loc.name
            }
        } catch {
            // 城市名获取失败不影响天气功能
        }

        return "未知"
    }

    /// 在主线程上获取定位，解决 CLLocationManager 必须在主线程使用的问题
    private func getCurrentLocation() async throws -> CLLocation {
        try await LocationHelper.requestLocation()
    }

    // MARK: - Timeout Helper

    /// 带超时的 async 包装：超过指定秒数自动抛错，不会卡死 actor
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw WeatherError.timeout
            }
            // 第一个完成的 task 返回结果，取消另一个
            guard let result = try await group.next() else {
                throw WeatherError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Location Helper (MainActor)

/// 在主线程管理 CLLocationManager 的生命周期，带 10 秒自动超时
@MainActor
private final class LocationHelper: NSObject, CLLocationManagerDelegate {
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var manager: CLLocationManager?
    private var timeoutTask: Task<Void, Never>?

    /// 持有当前活跃的 helper，防止被 ARC 释放
    private static var activeHelper: LocationHelper?

    /// 静态入口：从任意线程安全调用
    static func requestLocation() async throws -> CLLocation {
        let helper = await MainActor.run { LocationHelper() }
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                helper.continuation = continuation
                LocationHelper.activeHelper = helper
                helper.start()
            }
        }
    }

    private func start() {
        let mgr = CLLocationManager()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager = mgr

        // 10 秒自动超时
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.finish(with: .failure(WeatherService.WeatherError.locationUnavailable))
            }
        }

        let status = mgr.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            mgr.requestLocation()
        } else if status == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        } else {
            finish(with: .failure(WeatherService.WeatherError.locationUnavailable))
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager = nil

        switch result {
        case .success(let location):
            continuation?.resume(returning: location)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
        LocationHelper.activeHelper = nil  // 释放强引用
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.first {
                self.finish(with: .success(location))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(with: .failure(WeatherService.WeatherError.locationUnavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.finish(with: .failure(WeatherService.WeatherError.locationUnavailable))
            }
        }
    }
}
