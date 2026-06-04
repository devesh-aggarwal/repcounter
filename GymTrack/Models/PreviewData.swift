import Foundation
import SwiftData

/// In-memory container seeded with the real program for SwiftUI previews.
enum PreviewData {
    @MainActor
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Exercise.self, ProgressEntry.self,
            configurations: config
        )
        SeedData.seedIfNeeded(container.mainContext)
        return container
    }()
}
