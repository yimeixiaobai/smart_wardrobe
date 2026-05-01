import SwiftUI

struct ColorHarmonyService {

    struct HarmonyResult {
        let score: Int              // 0-100
        let level: HarmonyLevel
        let description: String
        let suggestions: [String]
    }

    enum HarmonyLevel: String {
        case excellent = "excellent"
        case good = "good"
        case fair = "fair"
        case poor = "poor"

        var label: String {
            switch self {
            case .excellent: return "绝佳"
            case .good: return "协调"
            case .fair: return "一般"
            case .poor: return "冲突"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .poor: return .red
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "star.fill"
            case .good: return "hand.thumbsup.fill"
            case .fair: return "minus.circle"
            case .poor: return "exclamationmark.triangle.fill"
            }
        }
    }

    // MARK: - HSB representation

    struct HSBColor {
        let hue: Double        // 0-360
        let saturation: Double // 0-1
        let brightness: Double // 0-1

        var isNeutral: Bool {
            saturation < 0.15
        }

        var isBlack: Bool {
            brightness < 0.15
        }

        var isWhite: Bool {
            brightness > 0.9 && saturation < 0.1
        }

        var hueName: String {
            if isBlack { return "黑色系" }
            if isWhite { return "白色系" }
            if isNeutral { return "灰色系" }
            switch hue {
            case 0..<15, 345..<360: return "红色系"
            case 15..<45: return "橙色系"
            case 45..<75: return "黄色系"
            case 75..<150: return "绿色系"
            case 150..<210: return "青色系"
            case 210..<270: return "蓝色系"
            case 270..<345: return "紫色系"
            default: return "未知"
            }
        }
    }

    // MARK: - Public API

    static func analyze(hexColors: [[String]]) -> HarmonyResult {
        // Flatten all hex colors from all items, picking the first color per item as representative
        let representativeHexes = hexColors.compactMap(\.first)
        guard representativeHexes.count >= 2 else {
            return HarmonyResult(score: 100, level: .excellent, description: "添加更多单品来分析配色", suggestions: [])
        }

        let hsbColors = representativeHexes.map { hexToHSB($0) }

        // Separate into chromatic and neutral
        let chromatic = hsbColors.filter { !$0.isNeutral && !$0.isBlack && !$0.isWhite }
        let neutralCount = hsbColors.count - chromatic.count

        // If all neutral → always harmonious
        if chromatic.isEmpty {
            return HarmonyResult(
                score: 90,
                level: .excellent,
                description: "全中性色搭配，经典稳重",
                suggestions: ["可加入一件亮色单品作为点缀"]
            )
        }

        // If only one chromatic color + neutrals → safe combo
        if chromatic.count == 1 {
            return HarmonyResult(
                score: 85,
                level: .good,
                description: "单色+中性色，简洁干净",
                suggestions: ["尝试同色系的深浅变化增加层次"]
            )
        }

        // Analyze chromatic relationships
        let (matchType, matchScore) = analyzeColorRelationship(chromatic)
        let neutralBonus = min(neutralCount * 3, 10) // neutrals help mediate
        let finalScore = min(100, matchScore + neutralBonus)
        let level = scoreToLevel(finalScore)

        var suggestions: [String] = []
        if finalScore < 70 {
            suggestions.append("考虑用黑/白/灰单品过渡冲突色")
            suggestions.append("尝试调整为同色系或邻近色搭配")
        } else if finalScore < 85 {
            suggestions.append("整体不错，可微调色彩比例")
        }

        return HarmonyResult(
            score: finalScore,
            level: level,
            description: matchType,
            suggestions: suggestions
        )
    }

    // MARK: - Color Relationship Analysis

    private static func analyzeColorRelationship(_ colors: [HSBColor]) -> (description: String, score: Int) {
        let hues = colors.map { $0.hue }

        // Check all pairwise hue differences
        var minDiff: Double = 360
        var maxDiff: Double = 0
        var totalDiff: Double = 0
        var pairCount = 0

        for i in 0..<hues.count {
            for j in (i+1)..<hues.count {
                let diff = hueDifference(hues[i], hues[j])
                minDiff = min(minDiff, diff)
                maxDiff = max(maxDiff, diff)
                totalDiff += diff
                pairCount += 1
            }
        }

        let avgDiff = pairCount > 0 ? totalDiff / Double(pairCount) : 0

        // Classify the relationship
        if maxDiff <= 30 {
            // Monochromatic / analogous
            let satMax = colors.map(\.saturation).max() ?? 0
            let satMin = colors.map(\.saturation).min() ?? 0
            let briMax = colors.map(\.brightness).max() ?? 0
            let briMin = colors.map(\.brightness).min() ?? 0
            let satDiff = satMax - satMin
            let briDiff = briMax - briMin
            if satDiff > 0.3 || briDiff > 0.3 {
                return ("同色系深浅搭配，层次丰富", 92)
            }
            return ("同色系搭配，和谐统一", 88)
        }

        if maxDiff <= 60 {
            return ("邻近色搭配，自然协调", 85)
        }

        if pairCount == 1 {
            // Only two chromatic colors
            let diff = maxDiff
            if abs(diff - 180) <= 20 {
                // Complementary
                return ("互补色搭配，对比鲜明", 75)
            }
            if abs(diff - 120) <= 20 || abs(diff - 240) <= 20 {
                return ("三角配色关系，活泼有趣", 72)
            }
            if diff <= 90 {
                return ("类似色搭配，和谐舒适", 80)
            }
            return ("对比色搭配，视觉跳跃", 65)
        }

        // 3+ chromatic colors
        if isTriadic(hues) {
            return ("三角配色，均衡活泼", 70)
        }

        if avgDiff <= 60 {
            return ("整体色调接近，协调自然", 78)
        }

        if avgDiff > 100 {
            return ("多色对比强烈，风格大胆", 55)
        }

        return ("混合配色", 65)
    }

    private static func isTriadic(_ hues: [Double]) -> Bool {
        guard hues.count >= 3 else { return false }
        // Check if hues roughly form equal spacing (120° apart)
        let sorted = hues.sorted()
        for i in 0..<sorted.count {
            for j in (i+1)..<sorted.count {
                for k in (j+1)..<sorted.count {
                    let d1 = hueDifference(sorted[i], sorted[j])
                    let d2 = hueDifference(sorted[j], sorted[k])
                    let d3 = hueDifference(sorted[k], sorted[i])
                    if abs(d1 - 120) < 25 && abs(d2 - 120) < 25 && abs(d3 - 120) < 25 {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Helpers

    private static func hueDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        return min(diff, 360 - diff)
    }

    private static func scoreToLevel(_ score: Int) -> HarmonyLevel {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        default: return .poor
        }
    }

    static func hexToHSB(_ hex: String) -> HSBColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = maxC > 0 ? delta / maxC : 0
        let brightness = maxC

        return HSBColor(hue: hue, saturation: saturation, brightness: brightness)
    }
}
