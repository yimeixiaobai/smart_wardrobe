import Foundation
import Testing
@testable import SmartWardrobe

@Suite("IdleAnalysisService")
struct IdleAnalysisTests {
    let service = IdleAnalysisService.shared

    @Test("Active seasons include expected seasons for each month")
    func activeSeasonsMapping() {
        let jan = makeDate(month: 1)
        let jul = makeDate(month: 7)

        let winterSeasons = service.activeSeasons(at: jan)
        #expect(winterSeasons.contains("冬"))

        let summerSeasons = service.activeSeasons(at: jul)
        #expect(summerSeasons.contains("夏"))
    }

    @Test("Temperature overrides season when extreme")
    func temperatureOverride() {
        let aprilDate = makeDate(month: 4)

        let coldOverride = service.activeSeasons(at: aprilDate, temperature: -5)
        #expect(coldOverride.contains("冬"))

        let hotOverride = service.activeSeasons(at: aprilDate, temperature: 35)
        #expect(hotOverride.contains("夏"))
    }

    @Test("Idle threshold varies by season type")
    func idleThresholds() {
        let singleSeason = makeItem(seasons: ["夏"])
        let multiSeason = makeItem(seasons: ["春", "夏"])
        let allSeason = makeItem(seasons: [])

        #expect(service.idleThreshold(for: singleSeason) == 21)
        #expect(service.idleThreshold(for: multiSeason) == 30)
        #expect(service.idleThreshold(for: allSeason) == 60)
    }

    private func makeDate(month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    private func makeItem(seasons: [String]) -> ClothingItem {
        let item = ClothingItem(name: "Test")
        item.seasons = seasons
        return item
    }
}
