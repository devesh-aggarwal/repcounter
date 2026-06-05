import SwiftUI

struct RootView: View {
    @State private var selection = 0
    @StateObject private var restTimer = RestTimer()
    @State private var celebrations = CelebrationCenter.shared
    @State private var prefs = Preferences.shared

    private var coachAvailable: Bool { !prefs.openAIAPIKey.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                TrackView()
                    .tabItem {
                        Label("Today", systemImage: "dumbbell.fill")
                    }
                    .tag(0)

                StatsView()
                    .tabItem {
                        Label("Summary", systemImage: "chart.xyaxis.line")
                    }
                    .tag(1)

                if coachAvailable {
                    AIView()
                        .tabItem {
                            Label("Coach", systemImage: "sparkles")
                        }
                        .tag(2)
                }
            }

            if restTimer.isActive {
                RestTimerBar(timer: restTimer)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Fullscreen confetti overlay — drives PR celebrations from
            // anywhere in the app via CelebrationCenter.shared.celebrate().
            Confetti(trigger: celebrations.burstCount)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: restTimer.isActive)
        .environmentObject(restTimer)
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
