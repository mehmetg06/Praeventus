#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()

    var body: some View {
        // One shared atmosphere behind all tabs. Building it per-tab kept three
        // copies of every TimelineView/Canvas animation ticking at once (even
        // for off-screen tabs), tripling the rendering cost.
        ZStack {
            background

            TabView {
                HomeView(store: store)
                    .tabItem {
                        Label("tab.atmosphere", systemImage: "cloud.sun")
                    }

                WeatherLabView(store: store)
                    .tabItem {
                        Label("tab.lab", systemImage: "flask")
                    }

                SettingsView()
                    .tabItem {
                        Label("tab.settings", systemImage: "gearshape")
                    }
            }
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