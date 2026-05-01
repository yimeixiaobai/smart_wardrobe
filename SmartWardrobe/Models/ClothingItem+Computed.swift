import Foundation

// MARK: - 计算属性扩展
// 不写入数据库，仅基于已有字段派生的便利属性，供 IdleAnalysisService / TodayView / CPW 排行使用

extension ClothingItem {

    /// 最后一次穿着日期（取所有穿搭记录的最大日期）
    var lastWornDate: Date? {
        wearRecordItems
            .compactMap { $0.wearRecord?.date }
            .max()
    }

    /// 距最后一次穿着的天数（从未穿过返回 nil）
    var daysSinceLastWorn: Int? {
        guard let last = lastWornDate else { return nil }
        return Calendar.current.dateComponents([.day],
                                               from: Calendar.current.startOfDay(for: last),
                                               to: Calendar.current.startOfDay(for: Date())).day
    }

    /// 距购入（或添加）的天数
    var daysSinceAcquired: Int {
        let base = purchaseDate ?? createdAt
        return Calendar.current.dateComponents([.day],
                                               from: Calendar.current.startOfDay(for: base),
                                               to: Calendar.current.startOfDay(for: Date())).day ?? 0
    }

    /// 每次穿着成本 = 价格 / 穿着次数
    var costPerWear: Double? {
        guard let price = purchasePrice, price > 0, wearCount > 0 else { return nil }
        return price / Double(wearCount)
    }

    /// 季节归属分类
    enum SeasonType: Equatable {
        case allSeason                  // 全季节（无标签或 4 季全有）
        case singleSeason(String)       // 单季节（如冬装羽绒服）
        case multiSeason([String])      // 多季节（春秋装）
    }

    var seasonType: SeasonType {
        if seasons.isEmpty || seasons.count >= 4 {
            return .allSeason
        }
        if seasons.count == 1 {
            return .singleSeason(seasons[0])
        }
        return .multiSeason(seasons)
    }
}
