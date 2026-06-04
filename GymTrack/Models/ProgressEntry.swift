import Foundation
import SwiftData

@Model
final class ProgressEntry {
    var id: UUID = UUID()
    var value: Double = 0
    var date: Date = Date()
    var exercise: Exercise?

    init(value: Double, date: Date = Date(), exercise: Exercise? = nil) {
        self.id = UUID()
        self.value = value
        self.date = date
        self.exercise = exercise
    }
}
