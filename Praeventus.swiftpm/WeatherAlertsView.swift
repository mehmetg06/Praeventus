#if canImport(SwiftUI)
import SwiftUI

/// Lists official coordinate-bearing weather/disaster alerts (NWS + MeteoAlarm
/// + GDACS, combined by the backend into one shared global payload — see
/// `deno/weather.ts` `handleAlerts`). Tapping a row loads that location into
/// `WeatherStore` and switches to the Atmosphere tab, mirroring how
/// `HomeView.selectSuggestion` handles a search result.
struct WeatherAlertsView: View {
    @ObservedObject var store: WeatherStore
    @Binding var selectedTab: RootTab

    @State private var alerts: [WeatherAlert] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var provider: CloudflareWeatherProvider {
        CloudflareWeatherProvider(baseURL: WeatherSettings.backendBaseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .task { await loadAlerts() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "alerts.title", defaultValue: "Alerts"))
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundStyle(.white)
            Text(String(localized: "alerts.subtitle", defaultValue: "Official NWS, MeteoAlarm & GDACS warnings"))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && alerts.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if alerts.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(alerts) { alert in
                    Button {
                        Task { await select(alert) }
                    } label: {
                        AlertRow(alert: alert)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await loadAlerts() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text(loadError ?? String(localized: "alerts.empty", defaultValue: "No active alerts"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Actions

    private func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            alerts = try await provider.alerts()
            loadError = nil
        } catch {
            loadError = String(localized: "alerts.loadFailed", defaultValue: "Couldn't load alerts")
        }
    }

    private func select(_ alert: WeatherAlert) async {
        await store.load(
            latitude: alert.latitude,
            longitude: alert.longitude,
            name: alert.area,
            country: alert.country ?? ""
        )
        selectedTab = .atmosphere
    }
}

// MARK: - Row

private struct AlertRow: View {
    let alert: WeatherAlert

    var body: some View {
        VisionGlassCard(cornerRadius: 20) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(severityColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !alert.area.isEmpty || !(alert.country ?? "").isEmpty {
                        Text([alert.area, alert.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text(alert.source)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        Text(severityLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(severityColor)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
        }
    }

    private var severityColor: Color {
        switch alert.severity {
        case "extreme": return .red
        case "severe": return .orange
        case "moderate": return .yellow
        case "minor": return .blue
        default: return .gray
        }
    }

    private var severityLabel: String {
        switch alert.severity {
        case "extreme": return String(localized: "alerts.severity.extreme", defaultValue: "Extreme")
        case "severe": return String(localized: "alerts.severity.severe", defaultValue: "Severe")
        case "moderate": return String(localized: "alerts.severity.moderate", defaultValue: "Moderate")
        case "minor": return String(localized: "alerts.severity.minor", defaultValue: "Minor")
        default: return String(localized: "alerts.severity.unknown", defaultValue: "Unknown")
        }
    }
}
#endif
