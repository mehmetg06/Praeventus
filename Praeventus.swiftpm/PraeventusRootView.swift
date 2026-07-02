#if canImport(SwiftUI)
import SwiftUI

/// Identifies each tab so `WeatherAlertsView` can switch the selection back to
/// Atmosphere/Home after loading a tapped alert's location.
enum RootTab: Hashable {
    case atmosphere, map, alerts, lab, settings
}

struct PraeventusRootView: View {
    @StateObject private var store = WeatherStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .atmosphere
    /// One instance shared between every `HomeView`'s scroll view and the
    /// background, managed as a StateObject.
    @StateObject private var scrollTracker = ScrollOffsetTracker()

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Tab content ──────────────────────────────────────────
            Group {
                switch selectedTab {
                case .atmosphere:
                    HomeView(store: store, scrollTracker: scrollTracker)
                        .background { atmosphereBackground }
                case .map:
                    if WeatherSettings.mapTabEnabled {
                        NavigationStack {
                            WeatherMapView(store: store)
                                .background { atmosphereBackground }
                        }
                    } else {
                        HomeView(store: store, scrollTracker: scrollTracker)
                            .background { atmosphereBackground }
                    }
                case .alerts:
                    if WeatherSettings.alertsTabEnabled {
                        WeatherAlertsView(store: store, selectedTab: $selectedTab)
                            .background { atmosphereBackground }
                    } else {
                        HomeView(store: store, scrollTracker: scrollTracker)
                            .background { atmosphereBackground }
                    }
                case .lab:
                    WeatherLabView(store: store)
                        .background { atmosphereBackground }
                case .settings:
                    SettingsView()
                        .background { atmosphereBackground }
                }
            }
            .ignoresSafeArea()

            // ── Floating Dock ─────────────────────────────────────────
            FloatingDock(selectedTab: $selectedTab)
                .padding(.bottom, 28)
        }
        .ignoresSafeArea()
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

    // Atmosphere background — shared so the Meeus solar-position math runs once per render.
    private var atmosphereBackground: some View {
        let astro = store.astronomicalAnalysis(at: store.currentDate)
        let solarNoon = astro.sunriseSunset.sunrise
            .addingTimeInterval(astro.sunriseSunset.duration / 2)
        return AtmosphereBackgroundView(
            atmosphere: store.atmosphere,
            sunAltitude: astro.sunAltitude,
            isBeforeSolarNoon: store.currentDate < solarNoon,
            windSpeed: store.weather.windSpeed,
            scrollTracker: scrollTracker
        )
        .ignoresSafeArea()
    }
}

// MARK: - Floating Dock

/// Pill-shaped floating navigation dock that replaces the system TabBar.
/// Hovers above the content on a blur-backed capsule with a specular highlight ring.
private struct FloatingDock: View {
    @Binding var selectedTab: RootTab

    private struct DockItem {
        let tab: RootTab
        let icon: String
        let label: LocalizedStringKey
    }

    private var items: [DockItem] {
        var result: [DockItem] = [
            .init(tab: .atmosphere, icon: "cloud.sun.fill", label: "tab.atmosphere")
        ]
        if WeatherSettings.alertsTabEnabled {
            result.append(.init(tab: .alerts, icon: "exclamationmark.triangle.fill", label: "tab.alerts"))
        }
        if WeatherSettings.mapTabEnabled {
            result.append(.init(tab: .map, icon: "map.fill", label: "tab.map"))
        }
        result.append(.init(tab: .lab, icon: "flask.fill", label: "tab.lab"))
        result.append(.init(tab: .settings, icon: "gearshape.fill", label: "tab.settings"))
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                        selectedTab = item.tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21, weight: selectedTab == item.tab ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedTab == item.tab ? .white : .white.opacity(0.42))
                            .scaleEffect(selectedTab == item.tab ? 1.12 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: selectedTab)

                        // Active indicator dot
                        Circle()
                            .fill(.white.opacity(selectedTab == item.tab ? 0.80 : 0))
                            .frame(width: 4, height: 4)
                            .animation(.easeInOut(duration: 0.20), value: selectedTab)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .background {
            // Heavier shadow than a regular card so the dock reads as floating.
            ThinGlassCapsule(shadowOpacity: 0.50, shadowRadius: 22, shadowY: 10)
        }
        .padding(.horizontal, 30)
    }
}
#endif
