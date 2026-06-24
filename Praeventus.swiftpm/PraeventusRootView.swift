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
        ZStack {
            AtmosphereBackgroundView(
                atmosphere: store.atmosphere,
                hour: store.weather.hour,
                windSpeed: store.weather.windSpeed
            )

            if store.atmosphere.backgroundMood == .wet || store.atmosphere.backgroundMood == .storm {
                DropSymbolLayer(
                    windSpeed: store.weather.windSpeed,
                    intensity: store.atmosphere.rainSignal == .high ? 0.88 : 0.55
                )
            }
        }
    }
}
#endif