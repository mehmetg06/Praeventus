#if canImport(SwiftUI)
import SwiftUI

struct PraeventusRootView: View {
    @State private var selectedTab: PraeventusTab = .atmosphere
    @State private var weather = WeatherData.mersin

    var body: some View {
        ZStack(alignment: .bottom) {
            AtmosphereBackgroundView(condition: weather.condition)

            Group {
                switch selectedTab {
                case .atmosphere:
                    HomeView(weather: weather)
                case .lab:
                    WeatherLabView(weather: $weather)
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaPadding(.bottom, 104)

            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
    }
}

enum PraeventusTab: String, CaseIterable, Identifiable {
    case atmosphere = "Atmosfer"
    case lab = "Lab"
    case settings = "Ayarlar"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .atmosphere: return "cloud.sun"
        case .lab: return "flask"
        case .settings: return "gearshape"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: PraeventusTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PraeventusTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 24, weight: .light))
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.66))
                    .background {
                        if selectedTab == tab {
                            ThinGlassShape(cornerRadius: 30, intensity: 0.34)
                                .matchedGeometryEffect(id: "selectedTabGlass", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(ThinGlassShape(cornerRadius: 34, intensity: 0.16))
    }

    @Namespace private var tabNamespace
}
#endif
