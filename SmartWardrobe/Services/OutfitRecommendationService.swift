import Foundation
import SwiftData
import os.log

actor OutfitRecommendationService {
    private let logger = Logger(subsystem: "SmartWardrobe", category: "Recommendation")
    static let shared = OutfitRecommendationService()

    // MARK: - Types

    struct OutfitRecommendation: Identifiable {
        let id = UUID()
        let items: [ClothingItem]
        let occasion: String
        let reason: String
        let stylingTip: String?
        let unmatchedIds: [String]
    }

    struct RecommendationResult {
        let recommendations: [OutfitRecommendation]
        let weather: WeatherService.WeatherInfo?
    }

    // LLM JSON response structure
    private struct LLMResponse: Codable {
        struct Recommendation: Codable {
            let items: [String]
            let occasion: String?
            let reason: String
            let styling_tip: String?
        }
        let recommendations: [Recommendation]
    }

    enum RecommendationError: LocalizedError {
        case noItems
        case tooFewItems
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noItems: return "衣橱中没有衣物，请先添加一些衣物"
            case .tooFewItems: return "衣物数量太少，建议添加更多衣物以获得更好的推荐"
            case .parsingFailed(let msg): return "推荐解析失败：\(msg)"
            }
        }
    }

    // MARK: - System Prompt

    private let systemPrompt = """
    你是一位专业的时尚搭配顾问，帮助用户从她的真实衣橱中搭配穿搭方案。

    规则：
    1. 你只能从用户提供的衣橱清单中选择单品，绝对不能推荐不存在的物品
    2. 必须返回严格的 JSON 格式
    3. 选择时综合考虑：颜色搭配协调性、季节适配、场合需求、材质搭配
    4. 用简洁的中文解释搭配理由，突出为什么这几件放在一起好看
    5. 尽量避免推荐最近频繁穿着的单品，给衣橱里的沉睡单品更多机会
    6. 每套搭配应包含上衣+下装（或连体装），可选配鞋、包、配饰
    7. 颜色搭配要协调：同色系、邻近色、互补色都可以，但要有理由

    返回 JSON 格式：
    {
      "recommendations": [
        {
          "items": ["短ID1", "短ID2", "短ID3"],
          "occasion": "适合的场合",
          "reason": "搭配理由（1-2句话，说明颜色/风格/材质的搭配逻辑）",
          "styling_tip": "穿搭小贴士（可选，比如如何卷袖口、塞衣角等）"
        }
      ]
    }
    """

    // MARK: - Public API

    /// Today's recommendation based on weather + season + occasion
    /// - Parameter overrideWeather: 若提供，跳过天气 fetch（用于"明日推荐"等场景）
    /// - Parameter contextLabel: 用户提示（"今天" / "明天"），喂给 LLM 作为 prompt 前缀
    func recommendToday(
        items: [ClothingItem],
        wearRecords: [WearRecord],
        occasion: String = "日常",
        overrideWeather: WeatherService.WeatherInfo? = nil,
        contextLabel: String = "今天",
        onPhaseChange: (@Sendable (RecommendationPhase) async -> Void)? = nil
    ) async throws -> RecommendationResult {
        guard !items.isEmpty else { throw RecommendationError.noItems }

        let activeItems = items.filter { $0.status != ClothingStatus.retired.rawValue }
        guard activeItems.count >= 3 else { throw RecommendationError.tooFewItems }

        // Phase 1: Fetch weather
        await onPhaseChange?(.fetchingWeather)

        var weather: WeatherService.WeatherInfo?
        if let overrideWeather {
            weather = overrideWeather
        } else if APIKeyManager.shared.isWeatherConfigured {
            weather = try? await WeatherService.shared.fetchWeather()
        }

        // Phase 2: Analyze wardrobe
        await onPhaseChange?(.analyzingWardrobe)

        let season = weather.map({ seasonFromTemperature($0.temperature) }) ?? WeatherService.shared.currentSeason()

        // Filter by season
        let seasonalItems = filterBySeason(activeItems, season: season)
        let itemsToUse = seasonalItems.count >= 5 ? seasonalItems : activeItems

        let (summary, idMap) = buildWardrobeSummary(items: itemsToUse)
        let historyContext = buildWearHistoryContext(records: wearRecords)

        var userPrompt = ""
        if let w = weather {
            userPrompt += "\(contextLabel)天气：\(w.city) \(w.temperature)°C \(w.condition)（体感 \(w.feelsLike)°C，湿度 \(w.humidity)%）\n"
        }
        userPrompt += "\(contextLabel)季节：\(season)\n"
        userPrompt += "场合偏好：\(occasion)\n\n"

        if !historyContext.isEmpty {
            userPrompt += "最近穿着记录（请避免重复推荐）：\n\(historyContext)\n\n"
        }

        userPrompt += "我的衣橱：\n\(summary)\n\n"
        userPrompt += "请推荐 3 套适合\(contextLabel)穿的搭配方案。每套搭配包括上衣、下装（或连体装），可选配鞋、包、配饰。"

        // Phase 3: Call LLM
        await onPhaseChange?(.generatingOutfit)

        let recommendations = try await callLLM(userPrompt: userPrompt, idMap: idMap)

        // Phase 4: Done
        await onPhaseChange?(.parsingResult)

        return RecommendationResult(recommendations: recommendations, weather: weather)
    }

    /// Item-based recommendation: "What goes well with this?"
    func recommendForItem(
        targetItem: ClothingItem,
        allItems: [ClothingItem],
        wearRecords: [WearRecord],
        onPhaseChange: (@Sendable (ItemRecommendationPhase) async -> Void)? = nil
    ) async throws -> [OutfitRecommendation] {
        let activeItems = allItems.filter { $0.status != ClothingStatus.retired.rawValue && $0.id != targetItem.id }
        guard !activeItems.isEmpty else { throw RecommendationError.tooFewItems }

        // Phase 1: Analyze item & wardrobe
        await onPhaseChange?(.analyzingItem)

        // Get complementary category items
        let complementaryItems = getComplementaryItems(for: targetItem, from: activeItems)
        let itemsToSummarize = complementaryItems.isEmpty ? activeItems : complementaryItems

        // Build color harmony context
        let harmonyContext = buildHarmonyContext(target: targetItem, candidates: itemsToSummarize)

        let (summary, idMap) = buildWardrobeSummary(items: itemsToSummarize)
        let targetSummary = buildItemDetail(targetItem)
        let historyContext = buildWearHistoryContext(records: wearRecords)

        var userPrompt = "我想用这件单品搭配：\n\(targetSummary)\n\n"

        if !harmonyContext.isEmpty {
            userPrompt += "与其他单品的配色和谐度参考：\n\(harmonyContext)\n\n"
        }

        if !historyContext.isEmpty {
            userPrompt += "最近穿着记录：\n\(historyContext)\n\n"
        }

        userPrompt += "衣橱中可搭配的单品：\n\(summary)\n\n"
        userPrompt += "请推荐 3 种搭配方案，每个方案说明为什么这样搭配好看。注意：items 数组中必须包含目标单品的 ID。"

        // Add target to idMap
        var fullIdMap = idMap
        let targetShortId = shortId(targetItem.id)
        fullIdMap[targetShortId] = targetItem

        // Phase 2: Call LLM
        await onPhaseChange?(.generatingOutfit)

        let results = try await callLLM(userPrompt: userPrompt, idMap: fullIdMap)

        // Phase 3: Done
        await onPhaseChange?(.parsingResult)

        return results
    }

    // MARK: - Wardrobe Summarization

    private func buildWardrobeSummary(items: [ClothingItem]) -> (String, [String: ClothingItem]) {
        var idMap: [String: ClothingItem] = [:]
        var jsonItems: [[String: Any]] = []

        for item in items.prefix(80) { // Cap at 80 items to stay within token limits
            let sid = shortId(item.id)
            idMap[sid] = item

            var json: [String: Any] = [
                "id": sid,
                "name": item.displayName,
                "category": categoryPath(item)
            ]

            if !item.colorHexValues.isEmpty {
                let colorNames = item.colorHexValues.compactMap { hex in
                    AppConstants.PresetColors.all.first { $0.hex == hex }?.name ?? hex
                }
                json["colors"] = colorNames
            }
            if let style = item.colorStyle { json["colorStyle"] = style }
            if !item.seasons.isEmpty { json["seasons"] = item.seasons }
            if let material = item.material { json["material"] = material }
            if let sleeveLength = item.sleeveLength { json["sleeveLength"] = sleeveLength }
            if !item.tags.isEmpty { json["tags"] = item.tags }
            json["wearCount"] = item.wearCount

            jsonItems.append(json)
        }

        // Serialize to compact JSON string
        let data = try? JSONSerialization.data(withJSONObject: jsonItems, options: [.sortedKeys])
        let summary = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return (summary, idMap)
    }

    private func buildItemDetail(_ item: ClothingItem) -> String {
        var parts: [String] = []
        parts.append("ID: \(shortId(item.id))")
        parts.append("名称: \(item.displayName)")
        parts.append("分类: \(categoryPath(item))")

        if !item.colorHexValues.isEmpty {
            let names = item.colorHexValues.compactMap { hex in
                AppConstants.PresetColors.all.first { $0.hex == hex }?.name ?? hex
            }
            parts.append("颜色: \(names.joined(separator: "、"))")
        }
        if let style = item.colorStyle { parts.append("图案: \(style)") }
        if !item.seasons.isEmpty { parts.append("季节: \(item.seasons.joined(separator: "、"))") }
        if let material = item.material { parts.append("材质: \(material)") }
        if let sleeve = item.sleeveLength { parts.append("袖长: \(sleeve)") }
        if let collar = item.collarType { parts.append("领型: \(collar)") }

        return parts.joined(separator: "\n")
    }

    // MARK: - Wear History

    private func buildWearHistoryContext(records: [WearRecord]) -> String {
        let recent = records
            .sorted { $0.date > $1.date }
            .prefix(15) // Last 15 records

        if recent.isEmpty { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"

        return recent.map { record in
            let dateStr = formatter.string(from: record.date)
            let itemNames = record.allClothingItems.map { "\($0.displayName)(\(shortId($0.id)))" }
            return "- \(dateStr): \(itemNames.joined(separator: " + "))"
        }.joined(separator: "\n")
    }

    // MARK: - Color Harmony

    private func buildHarmonyContext(target: ClothingItem, candidates: [ClothingItem]) -> String {
        guard !target.colorHexValues.isEmpty else { return "" }

        var results: [(name: String, score: Int)] = []
        for candidate in candidates.prefix(20) {
            guard !candidate.colorHexValues.isEmpty else { continue }
            let harmony = ColorHarmonyService.analyze(hexColors: [target.colorHexValues, candidate.colorHexValues])
            results.append((name: "\(candidate.displayName)(\(shortId(candidate.id)))", score: harmony.score))
        }

        results.sort { $0.score > $1.score }
        let top10 = results.prefix(10)

        return top10.map { "- \($0.name): 和谐度 \($0.score)/100" }.joined(separator: "\n")
    }

    // MARK: - Complementary Categories

    private func getComplementaryItems(for item: ClothingItem, from items: [ClothingItem]) -> [ClothingItem] {
        let topCatName = item.topCategory?.name ?? ""

        // Define which categories complement each other
        let complementMap: [String: [String]] = [
            "上衣": ["裤子", "半身裙", "鞋", "包", "帽子", "首饰", "配饰"],
            "裤子": ["上衣", "鞋", "包", "帽子", "首饰", "配饰"],
            "半身裙": ["上衣", "鞋", "包", "帽子", "首饰", "配饰"],
            "连体装": ["鞋", "包", "帽子", "首饰", "配饰"],
            "鞋": ["上衣", "裤子", "半身裙", "连体装", "包"],
            "包": ["上衣", "裤子", "半身裙", "连体装", "鞋"],
            "帽子": ["上衣", "裤子", "半身裙", "连体装"],
            "首饰": ["上衣", "裤子", "半身裙", "连体装"],
            "配饰": ["上衣", "裤子", "半身裙", "连体装"]
        ]

        let targetCategories = complementMap[topCatName] ?? []
        if targetCategories.isEmpty { return items }

        return items.filter { item in
            let cat = item.topCategory?.name ?? ""
            return targetCategories.contains(cat)
        }
    }

    // MARK: - Season Helpers

    private func filterBySeason(_ items: [ClothingItem], season: String) -> [ClothingItem] {
        items.filter { $0.seasons.isEmpty || $0.seasons.contains(season) }
    }

    private func seasonFromTemperature(_ temp: Int) -> String {
        switch temp {
        case ...5: return "冬"
        case 6...15: return "春"
        case 16...25: return "秋"
        default: return "夏"
        }
    }

    // MARK: - LLM Call & Parse

    private func callLLM(userPrompt: String, idMap: [String: ClothingItem]) async throws -> [OutfitRecommendation] {
        let messages: [LLMService.ChatMessage] = [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userPrompt)
        ]

        let responseText = try await LLMService.shared.chat(messages: messages)

        return try parseRecommendations(from: responseText, idMap: idMap)
    }

    private func parseRecommendations(from jsonText: String, idMap: [String: ClothingItem]) throws -> [OutfitRecommendation] {
        // 提取 JSON（LLM 可能用 markdown 包裹）
        let cleanJSON: String
        if let range = jsonText.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            cleanJSON = String(jsonText[range])
        } else {
            cleanJSON = jsonText
        }

        guard let data = cleanJSON.data(using: .utf8) else {
            throw RecommendationError.parsingFailed("无法解码文本")
        }

        let llmResponse: LLMResponse
        do {
            llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
        } catch {
            throw RecommendationError.parsingFailed(error.localizedDescription)
        }

        return llmResponse.recommendations.compactMap { rec in
            var resolvedItems: [ClothingItem] = []
            var unmatchedIds: [String] = []

            for itemId in rec.items {
                if let item = idMap[itemId] {
                    resolvedItems.append(item)
                } else {
                    unmatchedIds.append(itemId)
                }
            }

            if !unmatchedIds.isEmpty {
                logger.warning("LLM returned unresolved item IDs: \(unmatchedIds.joined(separator: ", "))")
            }

            guard !resolvedItems.isEmpty else {
                logger.warning("Recommendation dropped: no matched items in \(rec.items)")
                return nil
            }

            return OutfitRecommendation(
                items: resolvedItems,
                occasion: rec.occasion ?? "日常",
                reason: rec.reason,
                stylingTip: rec.styling_tip,
                unmatchedIds: unmatchedIds
            )
        }
    }

    // MARK: - Utilities

    private func shortId(_ uuid: UUID) -> String {
        String(uuid.uuidString.prefix(8)).lowercased()
    }

    private func categoryPath(_ item: ClothingItem) -> String {
        if let parent = item.category?.parent {
            return "\(parent.name)/\(item.category?.name ?? "")"
        }
        return item.category?.name ?? "未分类"
    }
}
