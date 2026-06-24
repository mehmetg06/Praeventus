#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()

    var body: some View {
        TabView {
            ZStack {
                AtmosphereBackgroundView(
                    atmosphere: store.atmosphere,
                    hour: store.weather.hour,
                    windSpeed: store.weather.windSpeed
                )
                HomeView(store: store)
            }
            .tabItem {
                Label("Atmosfer", systemImage: "cloud.sun")
            }

            ZStack {
                AtmosphereBackgroundView(
                    atmosphere: store.atmosphere,
                    hour: store.weather.hour,
                    windSpeed: store.weather.windSpeed
                )
                WeatherLabView(store: store)
            }
            .tabItem {
                Label("Lab", systemImage: "flask")
            }

            ZStack {
                AtmosphereBackgroundView(
                    atmosphere: store.atmosphere,
                    hour: store.weather.hour,
                    windSpeed: store.weather.windSpeed
                )
                SettingsView()
            }
            .tabItem {
                Label("Ayarlar", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif