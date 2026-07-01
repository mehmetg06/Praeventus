#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Identifies each tab so `WeatherAlertsView` can switch the selection back to
/// Atmosphere/Home after loading a tapped alert's location.
enum RootTab: Hashable {
    case atmosphere, map, alerts, lab, settings
}

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .atmosphere

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
        TabView(selection: $selectedTab) {
            HomeView(store: store)
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.atmosphere", systemImage: "cloud.sun")
                }
                .tag(RootTab.atmosphere)

            if WeatherSettings.mapTabEnabled {
                NavigationStack {
                    WeatherMapView(store: store)
                        .background { atmosphereBackground }
                }
                .tabItem {
                    Label("tab.map", systemImage: "map.fill")
                }
                .tag(RootTab.map)
            }

            if WeatherSettings.alertsTabEnabled {
                WeatherAlertsView(store: store, selectedTab: $selectedTab)
                    .background { atmosphereBackground }
                    .tabItem {
                        Label("tab.alerts", systemImage: "exclamationmark.triangle")
                    }
                    .tag(RootTab.alerts)
            }

            WeatherLabView(store: store)
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.lab", systemImage: "flask")
                }
                .tag(RootTab.lab)

            SettingsView()
                .background { atmosphereBackground }
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .toolbarBackground(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        // Push the sandbox overrides into the whole tree so the shared
        // atmosphere, glass and particle layers react in real time.
        .environment(\.performanceMode, store.performanceMode)
        .environment(\.showLayoutBounds, store.showLayoutBounds)
        .environment(\.sandboxAnimationSpeed, store.animationSpeed)
        .environment(\.moonCycleOverride, store.moonPhaseOverride?.cyclePosition ?? -1)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.resumeSensors()
            } else {
                store.suspendSensors()
            }
        }
        .task {
            // Restore the last location (if any) on launch.
            await store.restoreOrPrompt()
        }
    }

    // Rendered inside each tab's UIHostingController so the atmosphere shows
    // through the SwiftUI content tree, bypassing UITabBarController's opaque
    // UIKit backing that would cover a shared ZStack background layer.
    private var atmosphereBackground: some View {
        let astro = store.astronomicalAnalysis(at: store.currentDate)
        let solarNoon = astro.sunriseSunset.sunrise
            .addingTimeInterval(astro.sunriseSunset.duration / 2)
        return AtmosphereBackgroundView(
            atmosphere: store.atmosphere,
            sunAltitude: astro.sunAltitude,
            isBeforeSolarNoon: store.currentDate < solarNoon,
            windSpeed: store.weather.windSpeed
        )
        .ignoresSafeArea()
    }
}
#endif