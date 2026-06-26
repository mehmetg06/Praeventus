#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PraeventusRootView: View {
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
        // One shared atmosphere behind all tabs. Building it per-tab kept three
        // copies of every TimelineView/Canvas animation ticking at once (even
        // for off-screen tabs), tripling the rendering cost.
        ZStack {
            background

            TabView {
                HomeView(store: store)
                    .background(Color.clear)
                    .tabItem {
                        Label("tab.atmosphere", systemImage: "cloud.sun")
                    }

                WeatherLabView(store: store)
                    .background(Color.clear)
                    .tabItem {
                        Label("tab.lab", systemImage: "flask")
                    }

                SettingsView()
                    .background(Color.clear)
                    .tabItem {
                        Label("tab.settings", systemImage: "gearshape")
                    }
            }
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .tabBar)
        }
        .preferredColorScheme(.dark)
        .task {
            // Restore the last location (if any) on launch.
            await store.restoreOrPrompt()
        }
    }

    private var background: some View {
        AtmosphereBackgroundView(
            atmosphere: store.atmosphere,
            hour: store.weather.hour,
            windSpeed: store.weather.windSpeed
        )
    }
}
#endif