import UIKit

/// Lightweight wrapper around UIKit haptic generators.
enum Haptics {
    static func tick() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Pulse the device once per completed set so you can feel *how many* sets
    /// you've logged without looking at the screen — one tap per set, then a
    /// success flourish when you hit your target. Pulses are capped so a long
    /// session never buzzes endlessly; the on-screen count stays exact.
    static func setLogged(count: Int, target: Int) {
        let pulses = max(1, min(count, 6))
        let spacing = 0.16
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        for i in 0..<pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * spacing) {
                generator.impactOccurred()
                generator.prepare()
            }
        }
        if target > 0 && count >= target {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(pulses) * spacing + 0.1) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}
