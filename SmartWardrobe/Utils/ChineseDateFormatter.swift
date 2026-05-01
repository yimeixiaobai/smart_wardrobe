import Foundation

/// 统一的中文日期格式化工具，确保在任何系统语言下都显示中文日期
enum ChineseDateFormatter {
    private static let zhLocale = Locale(identifier: "zh_CN")

    // MARK: - Formatters (lazy, thread-safe)

    /// 2026年4月 — 用于日历月导航
    private static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "yyyy年M月"
        return f
    }()

    /// 4月14日 星期一 — 用于选中日期、穿搭记录
    private static let monthDayWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    /// 2026年4月14日 星期一 — 用于记录详情
    private static let fullDateWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f
    }()

    /// 2026年4月14日 — 用于购买日期等
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// 4月14日 — 用于统计周标签、搭配命名
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "M月d日"
        return f
    }()

    // MARK: - Public API

    /// "2026年4月"
    static func yearMonth(_ date: Date) -> String {
        yearMonthFormatter.string(from: date)
    }

    /// "4月14日 星期一"
    static func monthDayWeekday(_ date: Date) -> String {
        monthDayWeekdayFormatter.string(from: date)
    }

    /// "2026年4月14日 星期一"
    static func fullDateWeekday(_ date: Date) -> String {
        fullDateWeekdayFormatter.string(from: date)
    }

    /// "2026年4月14日"
    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    /// "4月14日"
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }
}
