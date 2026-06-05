import SwiftUI

/// One plate denomination and how many go on each side.
struct PlateStack: Identifiable {
    let id = UUID()
    let plate: Double
    let count: Int
}

struct PlateResult {
    let perSide: [PlateStack]
    /// The weight actually achievable with the available plates.
    let achievable: Double
    /// Remaining weight per side that could not be matched exactly.
    let leftoverPerSide: Double

    var isExact: Bool { leftoverPerSide < 0.001 }
    var isJustBar: Bool { perSide.isEmpty }
}

enum PlateMath {
    static func plates(for unit: String) -> [Double] {
        unit == "kg" ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5]
    }

    static func defaultBar(for unit: String) -> Double {
        unit == "kg" ? 20 : 45
    }

    /// Greedily fills each side of the bar from heaviest plate to lightest.
    static func compute(target: Double, bar: Double, plates: [Double]) -> PlateResult {
        let perSideWeight = max(0, (target - bar) / 2)
        var remaining = perSideWeight
        var stacks: [PlateStack] = []
        for plate in plates.sorted(by: >) {
            let count = Int((remaining / plate + 1e-9).rounded(.down))
            if count > 0 {
                stacks.append(PlateStack(plate: plate, count: count))
                remaining -= Double(count) * plate
            }
        }
        let achievable = bar + 2 * (perSideWeight - remaining)
        return PlateResult(perSide: stacks, achievable: achievable, leftoverPerSide: remaining)
    }

    /// Distinct, visually pleasing colors keyed by plate denomination.
    static func color(for plate: Double) -> Color {
        switch plate {
        case 45, 25, 20: return Color(hex: "#40C4FF")
        case 35, 15: return Color(hex: "#FFD740")
        case 10: return Color(hex: "#00E676")
        case 5: return Color(hex: "#FF6E40")
        default: return Color(hex: "#7C4DFF")
        }
    }
}
