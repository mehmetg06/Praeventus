#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PraeventusRootView: View {
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var store = WeatherStore()

    init() {
        #if canImport(UIKit)
        // Make the tab bar itself transparent so the shared atmosphere shows through.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some View {
        TabView {
            HomeView(store: store)
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.atmosphere", systemImage: "cloud.sun")
                }

            WeatherLabView(store: store)
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.lab", systemImage: "flask")
                }

            SettingsView()
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
        }
        .toolbarBackground(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        // Push the sandbox overrides into the whole tree so the shared
        // atmosphere, glass and particle layers react in real time.
        .environment(\.performanceMode, store.performanceMode)
        .environment(\.showLayoutBounds, store.showLayoutBounds)
        .environment(\.sandboxAnimationSpeed, store.animationSpeed)
        .environment(\.moonCycleOverride, store.moonPhaseOverride?.cyclePosition ?? -1)
        .task {
            // Restore the last location (if any) on launch.
            await store.restoreOrPrompt()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                store.pauseSensors()
            case .active:
                store.resumeSensors()
            @unknown default:
                break
            }
        }
    }

    // Rendered inside each tab's UIHostingController so the atmosphere shows
    // through the SwiftUI content tree, bypassing UITabBarController's opaque
    // UIKit backing that would cover a shared ZStack background layer.
    private var atmosphereBackground: some View {
        AtmosphereBackgroundView(
            atmosphere: store.atmosphere,
            hour: store.weather.hour,
            windSpeed: store.weather.windSpeed
        )
        .ignoresSafeArea()
    }
}
#endif