import SwiftUI

/// 顶部天气 + 日期条
struct TodayWeatherBar: View {
    let targetDay: TargetDay
    let weather: DisplayWeather?
    let isLoading: Bool
    var errorMessage: String?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine())
                    .font(.subheadline.bold())
                if let weather {
                    Text("\(weather.city) · \(seasonLabel())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(seasonLabel())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let weather {
                HStack(spacing: 8) {
                    Image(systemName: weatherIcon(weather.condition))
                        .font(.title2)
                        .foregroundStyle(iconColor(weather.condition))
                    VStack(alignment: .trailing, spacing: 0) {
                        tempDisplay(weather)
                        Text(weather.condition)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let error = errorMessage {
                Button {
                    onRetry?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else if !APIKeyManager.shared.isWeatherConfigured {
                Text("未配置天气")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func tempDisplay(_ weather: DisplayWeather) -> some View {
        if let range = weather.tempRange {
            // 明日：显示 min-max
            Text("\(range.min)-\(range.max)°")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        } else {
            // 今日：显示当前温度
            Text("\(weather.representativeTemp)°")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
    }

    // MARK: - Helpers

    private func dateLine() -> String {
        let targetDate = targetDay.date
        let prefix = targetDay == .tomorrow ? "明日 · " : ""
        return prefix + ChineseDateFormatter.monthDayWeekday(targetDate)
    }

    private func seasonLabel() -> String {
        let month = Calendar.current.component(.month, from: targetDay.date)
        switch month {
        case 3...5:  return "春季"
        case 6...8:  return "夏季"
        case 9...11: return "秋季"
        default:     return "冬季"
        }
    }

    private func weatherIcon(_ condition: String) -> String {
        if condition.contains("晴") { return "sun.max.fill" }
        if condition.contains("雪") { return "cloud.snow.fill" }
        if condition.contains("雨") { return "cloud.rain.fill" }
        if condition.contains("雾") { return "cloud.fog.fill" }
        if condition.contains("风") { return "wind" }
        if condition.contains("云") || condition.contains("阴") { return "cloud.fill" }
        return "cloud.sun.fill"
    }

    private func iconColor(_ condition: String) -> Color {
        if condition.contains("晴") { return .orange }
        if condition.contains("雪") { return .cyan }
        if condition.contains("雨") { return .blue }
        return .secondary
    }
}
