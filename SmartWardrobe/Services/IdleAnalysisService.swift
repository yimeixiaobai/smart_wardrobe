import Foundation

/// 闲置分析服务
///
/// 核心目标：不要把"季节性休眠"误报成"闲置"。
/// 例如 4 月的羽绒服、8 月的毛衣，它们只是不在活跃期，不是被忽略。
///
/// 算法概述：
/// 1. 双因子判断"当前活跃季节集"：基础月份映射 + 天气温度修正
/// 2. 根据衣物的 seasonType 判断是否在"活跃窗口"
/// 3. 只对在活跃窗口内的衣物做闲置判定
/// 4. 阈值差异化：单季装 21 天 / 多季装 30 天 / 全季装 60 天
/// 5. 季节首尾 14 天出特殊卡片（下架提醒 / 重新发现）
struct IdleAnalysisService {

    static let shared = IdleAnalysisService()

    // MARK: - 状态与结果

    enum IdleStatus: Equatable {
        case active                         // 最近穿过，正常
        case dormant                        // 季节性休眠（当季不适合，不报警）
        case neverWornInSeason              // 在活跃期但从未穿过（已过首个阈值期）
        case neverWornAcquiredRecent        // 刚买，还在首个活跃期
        case idleInSeason                   // 在活跃期但超过阈值天数没穿
        case highCPWInSeason                // 在活跃期 + 高 CPW
    }

    struct IdleEvaluation {
        let item: ClothingItem
        let status: IdleStatus
        /// 0-100，越高越该提醒
        let priority: Int
        /// 给用户看的一句话理由
        let reason: String
    }

    enum SpecialReminder {
        case none
        case seasonEnding(season: String, items: [ClothingItem])
        case seasonStarting(season: String, items: [ClothingItem])
    }

    // MARK: - 1. 活跃季节判断（双因子）

    /// 基于当前日期（月份）+ 可选温度，返回"当前活跃的季节集合"
    /// 过渡季返回 2 个季节；极端温度会覆盖月份判断
    func activeSeasons(at date: Date = Date(), temperature: Int? = nil) -> Set<String> {
        let month = Calendar.current.component(.month, from: date)

        // 基础：月份映射（包含过渡季）
        var base: Set<String>
        switch month {
        case 3, 4:   base = ["春"]
        case 5:      base = ["春", "夏"]            // 晚春过渡
        case 6, 7, 8: base = ["夏"]
        case 9:      base = ["夏", "秋"]            // 早秋过渡
        case 10, 11: base = ["秋"]
        case 12, 1:  base = ["冬"]
        case 2:      base = ["冬", "春"]            // 晚冬过渡
        default:     base = ["春"]
        }

        // 温度修正：极端值覆盖，中间值补足过渡
        if let temp = temperature {
            switch temp {
            case ..<5:
                base.insert("冬")
                base.remove("夏")
            case 5..<10:
                base.insert("冬")
                if (3...5).contains(month) { base.insert("春") }
                if (9...11).contains(month) { base.insert("秋") }
            case 10..<18:
                // 春秋温度
                if month <= 6 { base.insert("春") }
                else { base.insert("秋") }
            case 18..<25:
                // 暖和：春秋 + 可能的夏
                if month <= 6 { base.insert("春") }
                else { base.insert("秋") }
                if (5...9).contains(month) { base.insert("夏") }
            case 25...:
                base.insert("夏")
                base.remove("冬")
            default: break
            }
        }

        return base
    }

    // MARK: - 2. 活跃窗口判定

    func isInActiveWindow(_ item: ClothingItem, activeSeasons: Set<String>) -> Bool {
        switch item.seasonType {
        case .allSeason:
            return true
        case .singleSeason(let s):
            return activeSeasons.contains(s)
        case .multiSeason(let ss):
            return !Set(ss).isDisjoint(with: activeSeasons)
        }
    }

    // MARK: - 3. 闲置阈值

    /// 按衣物季节类型返回"多少天没穿算闲置"
    func idleThreshold(for item: ClothingItem) -> Int {
        switch item.seasonType {
        case .singleSeason: return 21   // 单季装活跃期短，要主动提醒
        case .multiSeason:  return 30
        case .allSeason:    return 60   // 全季装容忍度高
        }
    }

    // MARK: - 4. 单件评估

    func evaluate(_ item: ClothingItem, activeSeasons: Set<String>) -> IdleEvaluation {
        // 已淘汰 / 已借出 → 不参与
        if item.status == ClothingStatus.retired.rawValue || item.status == ClothingStatus.lentOut.rawValue {
            return IdleEvaluation(item: item, status: .active, priority: 0, reason: "")
        }

        // 不在活跃窗口 → 季节性休眠，不报警
        if !isInActiveWindow(item, activeSeasons: activeSeasons) {
            return IdleEvaluation(item: item, status: .dormant, priority: 0, reason: "当季不适合")
        }

        let threshold = idleThreshold(for: item)
        let daysAcquired = item.daysSinceAcquired

        // 情况 A：从未穿过
        if item.wearCount == 0 {
            if daysAcquired >= threshold {
                // 已过首个完整阈值期 → 高优先级
                if let price = item.purchasePrice, price >= 500 {
                    return IdleEvaluation(
                        item: item,
                        status: .neverWornInSeason,
                        priority: 100,
                        reason: "¥\(Int(price)) 买回来还没穿过哦"
                    )
                } else {
                    return IdleEvaluation(
                        item: item,
                        status: .neverWornInSeason,
                        priority: 90,
                        reason: "买了 \(daysAcquired) 天，还没首穿"
                    )
                }
            } else {
                // 还在首个活跃期，温柔提示
                return IdleEvaluation(
                    item: item,
                    status: .neverWornAcquiredRecent,
                    priority: 30,
                    reason: "新成员，还没首穿哦"
                )
            }
        }

        // 情况 B：穿过但可能很久没穿
        if let days = item.daysSinceLastWorn, days >= threshold {
            // 优先提示高 CPW（贵且穿得少）
            if let cpw = item.costPerWear, cpw >= 200 {
                return IdleEvaluation(
                    item: item,
                    status: .highCPWInSeason,
                    priority: 70,
                    reason: "穿 1 次值 ¥\(Int(cpw))，再穿一次更值"
                )
            }
            return IdleEvaluation(
                item: item,
                status: .idleInSeason,
                priority: 80,
                reason: "\(days) 天没穿了，今天试试?"
            )
        }

        return IdleEvaluation(item: item, status: .active, priority: 0, reason: "")
    }

    // MARK: - 5. 每日提醒列表

    /// 返回今天最该被提醒的 N 件衣物（按 priority 降序）
    func dailyReminders(items: [ClothingItem], temperature: Int? = nil, limit: Int = 3) -> [IdleEvaluation] {
        let active = activeSeasons(temperature: temperature)
        let evaluations = items.map { evaluate($0, activeSeasons: active) }
        return evaluations
            .filter { $0.priority > 0 && $0.status != .dormant && $0.status != .active }
            .sorted { $0.priority > $1.priority }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 6. 季节边界特殊提醒

    /// 季节首尾 14 天内出特殊卡片
    func specialReminder(items: [ClothingItem], date: Date = Date()) -> SpecialReminder {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)

        // 季节末：每季最后一个月的下半段
        let endingSeason: String? = {
            switch (month, day) {
            case (5, 15...): return "春"
            case (8, 15...): return "夏"
            case (11, 15...): return "秋"
            case (2, 15...): return "冬"
            default: return nil
            }
        }()

        if let ending = endingSeason {
            // 在本季内"还没穿过"的单季或双季衣物（全季的不在此列）
            let seasonStart = seasonStartDate(season: ending, year: year)
            let candidates = items.filter { item in
                guard item.status != ClothingStatus.retired.rawValue else { return false }
                guard !item.seasons.isEmpty,
                      item.seasons.contains(ending),
                      item.seasons.count <= 2
                else { return false }
                // 本季起点之后没有穿着记录
                if let last = item.lastWornDate, last >= seasonStart { return false }
                return true
            }.sorted { $0.daysSinceAcquired > $1.daysSinceAcquired }

            if !candidates.isEmpty {
                return .seasonEnding(season: ending, items: Array(candidates.prefix(5)))
            }
        }

        // 季节始：每季第一个月的上半段
        let startingSeason: String? = {
            switch (month, day) {
            case (3, 1...14): return "春"
            case (6, 1...14): return "夏"
            case (9, 1...14): return "秋"
            case (12, 1...14): return "冬"
            default: return nil
            }
        }()

        if let starting = startingSeason {
            // 当季衣物中，整体穿着次数最少的
            let candidates = items.filter { item in
                guard item.status != ClothingStatus.retired.rawValue else { return false }
                guard !item.seasons.isEmpty, item.seasons.contains(starting) else { return false }
                return true
            }.sorted { $0.wearCount < $1.wearCount }

            if !candidates.isEmpty {
                return .seasonStarting(season: starting, items: Array(candidates.prefix(5)))
            }
        }

        return .none
    }

    // MARK: - 7. 概览指标（给 Today 数据快照用）

    struct WardrobeMetrics {
        let totalItems: Int
        let dormantCount: Int        // 当季休眠数
        let idleInSeasonCount: Int   // 当季实际闲置数
        let activeCount: Int         // 当季正在使用
        /// 当季闲置率：当季衣物中闲置的占比（不含休眠）
        let idleRate: Double
        /// 平均 CPW（仅包含有价格且穿过的衣物）
        let averageCPW: Double?
    }

    func wardrobeMetrics(items: [ClothingItem], temperature: Int? = nil) -> WardrobeMetrics {
        let active = activeSeasons(temperature: temperature)
        let effective = items.filter { $0.status != ClothingStatus.retired.rawValue }

        var dormant = 0
        var idle = 0
        var activeInSeason = 0

        for item in effective {
            let eval = evaluate(item, activeSeasons: active)
            switch eval.status {
            case .dormant:
                dormant += 1
            case .idleInSeason, .neverWornInSeason, .highCPWInSeason:
                idle += 1
            case .active, .neverWornAcquiredRecent:
                // 刚买的新品算"活跃"里（还在观察期）
                activeInSeason += 1
            }
        }

        let inSeasonTotal = idle + activeInSeason
        let idleRate = inSeasonTotal > 0 ? Double(idle) / Double(inSeasonTotal) : 0

        let cpws = effective.compactMap { $0.costPerWear }
        let avgCPW = cpws.isEmpty ? nil : cpws.reduce(0, +) / Double(cpws.count)

        return WardrobeMetrics(
            totalItems: effective.count,
            dormantCount: dormant,
            idleInSeasonCount: idle,
            activeCount: activeInSeason,
            idleRate: idleRate,
            averageCPW: avgCPW
        )
    }

    // MARK: - Helpers

    private func seasonStartDate(season: String, year: Int) -> Date {
        let month: Int
        switch season {
        case "春": month = 3
        case "夏": month = 6
        case "秋": month = 9
        case "冬": month = 12
        default:   month = 1
        }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
}
