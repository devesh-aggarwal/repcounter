import SwiftUI

/// Workout categories. Push/Pull/Legs rotate; Misc is selectable but sits
/// outside the automatic rotation.
enum SplitDay: String, CaseIterable, Identifiable, Codable {
    case push
    case pull
    case legs
    case misc

    var id: String { rawValue }

    /// The three days that rotate automatically.
    static let rotation: [SplitDay] = [.push, .pull, .legs]

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .misc: return "Misc"
        }
    }

    var focus: String {
        switch self {
        case .push: return "Chest · Shoulders · Triceps"
        case .pull: return "Back · Biceps · Core"
        case .legs: return "Quads · Hamstrings · Calves"
        case .misc: return "Accessory & extras"
        }
    }

    var symbol: String {
        switch self {
        case .push: return "figure.strengthtraining.traditional"
        case .pull: return "figure.strengthtraining.functional"
        case .legs: return "figure.run"
        case .misc: return "ellipsis.circle.fill"
        }
    }

    var color: Color { Color(hex: colorHex) }

    var colorHex: String {
        switch self {
        case .push: return "#FF375F"
        case .pull: return "#0A84FF"
        case .legs: return "#30D158"
        case .misc: return "#AF52DE"
        }
    }

    /// The next rotating day. Misc routes back to Push.
    var next: SplitDay {
        guard let index = Self.rotation.firstIndex(of: self) else { return .push }
        return Self.rotation[(index + 1) % Self.rotation.count]
    }
}
