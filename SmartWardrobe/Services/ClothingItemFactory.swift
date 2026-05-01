import UIKit
import SwiftData

enum ClothingItemFactory {

    struct SaveInput {
        let processedImage: UIImage
        let originalImage: UIImage
        let preselectedCategory: Category?
        var name: String = ""
        var purchasePrice: Double?
        var purchaseDate: Date?
        var purchaseLink: String?
    }

    @MainActor
    static func createAndSave(
        input: SaveInput,
        context: ModelContext,
        onPhaseChange: ((SavingPhase) -> Void)? = nil
    ) async throws -> ClothingItem {
        onPhaseChange?(.savingImage)
        let result = try await ImageStorageService.shared.saveImages(
            processed: input.processedImage, original: input.originalImage
        )

        onPhaseChange?(.analyzingColor)
        async let signaturesResult = SimilarityCheckService.shared.computeSignatures(for: input.processedImage)
        async let recognitionResult = ClothingRecognitionService.shared.recognize(image: input.processedImage)

        onPhaseChange?(.recognizing)
        let signatures = await signaturesResult
        let recognition = await recognitionResult

        onPhaseChange?(.finishing)

        let item = ClothingItem()
        item.name = input.name
        item.purchasePrice = input.purchasePrice
        item.purchaseDate = input.purchaseDate
        item.purchaseLink = input.purchaseLink
        item.imageFileName = result.imageFileName
        item.originalImageFileName = result.originalFileName
        item.thumbnailFileName = result.thumbnailFileName
        item.imageHash = signatures.hash
        item.colorHistogramData = signatures.histogramData

        if let r = recognition {
            if let catName = r.categoryName {
                item.category = ClothingRecognitionService.shared.findCategory(named: catName, in: context)
            }
            if !r.colorHexValues.isEmpty { item.colorHexValues = r.colorHexValues }
            item.colorStyle = r.colorStyle
            item.material = r.material
            item.collarType = r.collarType
            item.sleeveLength = r.sleeveLength
            item.closureType = r.closureType
            item.pantLength = r.pantLength
            item.skirtLength = r.skirtLength
            item.heelHeight = r.heelHeight
            item.bagSize = r.bagSize
            if !r.seasons.isEmpty { item.seasons = r.seasons }
        }

        if item.category == nil {
            item.category = input.preselectedCategory
        }

        context.insert(item)
        try context.save()
        return item
    }
}
