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
                Label("Atmosfer", systemImage: "cloud.sun")
            }

            ZStack {
                background
                WeatherLabView(store: store)
            }
            .tabItem {
                Label("Lab", systemImage: "flask")
            }

            ZStack {
                background
                SettingsView()
            }
            .tabItem {
                Label("Ayarlar", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(.dark)
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