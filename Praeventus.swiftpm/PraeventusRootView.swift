#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @State private var weather = WeatherData.mersin

    var body: some View {
        TabView {
            ZStack {
                AtmosphereBackgroundView(condition: weather.condition)
                HomeView(weather: weather)
            }
            .tabItem {
                Label("Atmosfer", systemImage: "cloud.sun")
            }

            ZStack {
                AtmosphereBackgroundView(condition: weather.condition)
                WeatherLabView(weather: $weather)
            }
            .tabItem {
                Label("Lab", systemImage: "flask")
            }

            ZStack {
                AtmosphereBackgroundView(condition: weather.condition)
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