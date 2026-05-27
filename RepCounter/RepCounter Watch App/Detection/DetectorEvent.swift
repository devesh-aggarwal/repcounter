import Foundation

enum DetectorEvent: Equatable {
    case rep
    case setEnded(count: Int)
}
