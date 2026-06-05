import Foundation
import Observation

/// App-wide pulse for celebration moments (new PRs). Any view can call
/// `CelebrationCenter.shared.celebrate()` to bump `burstCount`; a fullscreen
/// `Confetti` overlay at the `RootView` level listens and fires.
///
/// Lives at app scope (not per-card) so the burst can render over the entire
/// screen — earlier, per-card confetti got clipped by the ScrollView and the
/// card's own rounded background, which is why nothing was visible.
@MainActor
@Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()
    var burstCount: Int = 0

    private init() {}

    func celebrate() {
        burstCount &+= 1
    }
}
