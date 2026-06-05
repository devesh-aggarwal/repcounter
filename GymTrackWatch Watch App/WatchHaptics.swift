import Foundation
import WatchKit

/// Watch-side haptic helpers. The Taptic Engine on the wrist is the whole
/// point here: completing a set buzzes the device once per set so you can feel
/// how many you've done without raising your arm to look. Mirrors the phone's
/// `Haptics.setLogged` so both wrists and pocket speak the same language.
enum WatchHaptics {
    /// Tap once per completed set, then a success notification when the target
    /// is reached. watchOS coalesces haptics fired too close together, so the
    /// pulses are spaced out and the count is capped for a long session.
    static func setLogged(count: Int, target: Int) {
        let pulses = max(1, min(count, 6))
        let spacing = 0.28
        let device = WKInterfaceDevice.current()
        for i in 0..<pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * spacing) {
                device.play(.click)
            }
        }
        if target > 0 && count >= target {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(pulses) * spacing + 0.15) {
                device.play(.success)
            }
        }
    }
}
