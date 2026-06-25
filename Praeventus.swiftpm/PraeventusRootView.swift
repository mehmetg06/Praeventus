#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()

    var body: some View {
        TabView {
            ZStack {
                background
                HomeView(store: store)
            }
            .tabItem {
                Label("tab.atmosphere", systemImage: "cloud.sun")
            }

            ZStack {
                background
                WeatherLabView(store: store)
            }
            .tabItem {
                Label("tab.lab", systemImage: "flask")
            }

            ZStack {
                background
                SettingsView()
            }
            .tabItem {
                Label("tab.settings", systemImage: "gearshape")
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