#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()
    @State private var selectedTab: PraeventusTab = .story

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            Group {
                switch selectedTab {
                case .radar, .forecast:
                    WeatherLabView(store: store)
                case .story:
                    HomeView(store: store)
                case .layers:
                    SettingsView()
                }
            }
            .padding(.bottom, 78)

            CustomGlassTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
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

enum PraeventusTab: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case story = "Hikâye"
    case forecast = "Tahmin"
    case layers = "Katman"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .radar: return "scope"
        case .story: return "sparkles"
        case .forecast: return "sun.max"
        case .layers: return "square.3.layers.3d"
        }
    }
}

private struct CustomGlassTabBar: View {
    @Binding var selectedTab: PraeventusTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PraeventusTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.52))
                    .background {
                        if selectedTab == tab {
                            Capsule(style: .continuous)
                                .fill(.blue.opacity(0.18))
                                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                                .shadow(color: .blue.opacity(0.45), radius: 18, y: 0)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(ThinGlassShape(cornerRadius: 30, intensity: 0.18, highlightOpacity: 0.20, innerShadowOpacity: 0.28, borderOpacity: 0.28))
    }
}
#endif
