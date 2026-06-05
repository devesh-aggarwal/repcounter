import SwiftUI
import SwiftData
import UIKit

@main
struct GymTrackApp: App {
    let container: ModelContainer

    init() {
        Self.configureAppearance()
        container = Self.makeContainer()
        SeedData.seedIfNeeded(container.mainContext)
    }

    /// Builds the SwiftData container with CloudKit sync when the iCloud
    /// entitlement is wired up and the user is signed in. Falls back to a
    /// local-only store otherwise, so the app still works without iCloud (or
    /// before the developer adds the CloudKit capability).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Exercise.self, ProgressEntry.self])

        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // CloudKit setup not present yet — fall back to a local store so
            // the app stays usable. Data created here will migrate into the
            // CloudKit-backed store the next launch after the entitlement is
            // added, because SwiftData reuses the same on-disk SQLite file.
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }

    /// Applies the dark, opaque chrome used across navigation and tab bars.
    private static func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.surface)
        tab.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
