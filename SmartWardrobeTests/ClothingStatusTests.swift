import Testing
@testable import SmartWardrobe

@Suite("ClothingStatus")
struct ClothingStatusTests {
    @Test("Raw values match Chinese strings used in predicates")
    func rawValues() {
        #expect(ClothingStatus.active.rawValue == "正常")
        #expect(ClothingStatus.lentOut.rawValue == "已借出")
        #expect(ClothingStatus.retired.rawValue == "已淘汰")
    }

    @Test("All cases match Constants.Status.all")
    func allCasesMatchConstants() {
        let enumValues = ClothingStatus.allCases.map(\.rawValue)
        #expect(enumValues == AppConstants.Status.all)
    }
}
