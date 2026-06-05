import SwiftUI

/// Apple Fitness–inspired dark design tokens with iOS 26-style materials.
enum Theme {
    // Surfaces (system dark grays on true black, like Fitness)
    static let background = Color(hex: "#000000")
    static let surface = Color(hex: "#1C1C1E")
    static let surfaceElevated = Color(hex: "#2C2C2E")
    static let stroke = Color.white.opacity(0.08)

    /// Adaptive translucent fills for controls.
    static let fill = Color.white.opacity(0.06)
    static let fillStrong = Color.white.opacity(0.12)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.3)

    // Brand / ring accents (Apple Fitness palette)
    static let accent = Color(hex: "#30D158")      // exercise green
    static let accentSoft = Color(hex: "#00D9C0")  // teal
    static let move = Color(hex: "#FF375F")        // move pink/red
    static let cardio = Color(hex: "#0A84FF")      // blue

    static let accentGradient = LinearGradient(
        colors: [Color(hex: "#30D158"), Color(hex: "#00D9C0")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent colors offered when customizing an exercise.
    static let palette: [String] = [
        "#30D158", "#00D9C0", "#0A84FF", "#5E5CE6",
        "#FF375F", "#FF9F0A", "#FFD60A", "#BF5AF2"
    ]

    /// SF Symbols offered when creating an exercise.
    static let icons: [String] = [
        "dumbbell.fill", "figure.strengthtraining.traditional", "figure.strengthtraining.functional",
        "figure.run", "figure.core.training", "bolt.fill",
        "flame.fill", "heart.fill", "scalemass.fill", "timer"
    ]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Double {
    /// Compact display: drops the decimal when the value is a whole number.
    var clean: String {
        rounded() == self ? String(Int(self)) : String(format: "%.1f", self)
    }
}

extension Date {
    /// A terse human-friendly relative string, e.g. "today", "3d ago", "Mar 4".
    var shortRelative: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "today" }
        if calendar.isDateInYesterday(self) { return "yesterday" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: self),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
