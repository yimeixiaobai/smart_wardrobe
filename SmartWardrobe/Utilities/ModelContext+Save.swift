import SwiftData
import os.log

extension ModelContext {
    private static let logger = Logger(subsystem: "SmartWardrobe", category: "Persistence")

    func safeSave() {
        do {
            try save()
        } catch {
            Self.logger.error("ModelContext.save 失败: \(error.localizedDescription)")
        }
    }
}
