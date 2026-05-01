import Testing
@testable import SmartWardrobe

@Suite("ColorHarmonyService")
struct ColorHarmonyTests {
    @Test("Same color scores high")
    func sameColorHighScore() {
        let result = ColorHarmonyService.analyze(hexColors: [["1A1A1A"], ["1A1A1A"]])
        #expect(result.score >= 70)
    }

    @Test("Empty input returns valid result")
    func emptyInput() {
        let result = ColorHarmonyService.analyze(hexColors: [])
        #expect(result.score >= 0)
    }

    @Test("Single item returns valid result")
    func singleItem() {
        let result = ColorHarmonyService.analyze(hexColors: [["CC2936"]])
        #expect(result.score >= 0)
    }
}
