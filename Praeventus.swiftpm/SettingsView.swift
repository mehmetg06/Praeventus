#if canImport(SwiftUI)
import SwiftUI

struct SettingsView: View {
    @State private var showActivityEditor = false
    @State private var activities = ActivityStorage.loadActivities()
    @AppStorage(WeatherSettings.multiModelKey) private var multiModelEnabled = true
    @AppStorage(WeatherSettings.sensorCalibrationKey) private var sensorCalibrationEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("settings.fusion.multiModel", isOn: $multiModelEnabled)
                    Toggle("settings.fusion.sensor", isOn: $sensorCalibrationEnabled)
                } header: {
                    Text("settings.fusion.title")
                } footer: {
                    Text("settings.fusion.footer")
                }

                Section("settings.activities.title") {
                    NavigationLink(destination: ActivityManagementView(activities: $activities)) {
                        Label("settings.activities.manage", systemImage: "figure.walk")
                    }
                }

                Section("settings.privacy.title") {
                    Label("settings.privacy.location", systemImage: "location.slash")
                    Label("settings.privacy.ip", systemImage: "network.slash")
                    Label("settings.privacy.onDevice", systemImage: "cpu")
                    Label("settings.privacy.noKey", systemImage: "key.slash")
                }

                Section("settings.about.title") {
                    LabeledContent("settings.about.source", value: "ECMWF / GFS / ICON (Deno Deploy)")
                    LabeledContent("settings.about.version", value: appVersion)
                    if let url = URL(string: "https://api.met.no") {
                        Link("Weather Data by MET Norway", destination: url)
                    }
                    if let url = URL(string: "https://brightsky.dev") {
                        Link("Weather Data by DWD (BrightSky)", destination: url)
                    }
                    if let url = URL(string: "https://www.openstreetmap.org/copyright") {
                        Link("Geocoding by OpenStreetMap", destination: url)
                    }
                }

                Section {
                    dataSourceRow(
                        name: "NOAA / aviationweather.gov",
                        description: "settings.attribution.noaa.desc",
                        license: "settings.attribution.publicDomain",
                        url: "https://aviationweather.gov"
                    )
                    dataSourceRow(
                        name: "Deutscher Wetterdienst (DWD)",
                        description: "settings.attribution.dwd.desc",
                        license: "CC BY 4.0",
                        url: "https://www.dwd.de/EN/service/copyright/copyright_artikel.html"
                    )
                    dataSourceRow(
                        name: "IEM / NEXRAD (Iowa Mesonet)",
                        description: "settings.attribution.iem.desc",
                        license: "settings.attribution.academic",
                        url: "https://mesonet.agron.iastate.edu"
                    )
                    dataSourceRow(
                        name: "NASA GIBS (GOES-East IR)",
                        description: "settings.attribution.gibs.desc",
                        license: "settings.attribution.publicDomain",
                        url: "https://nasa.github.io/gibs/"
                    )
                } header: {
                    Text("settings.attribution.title")
                } footer: {
                    Text("settings.attribution.footer")
                }

                Section {
                    Text("Praeventus tarafından sunulan UV indeksi, fırtına riski, sıcak çarpması veya hipotermi uyarıları açık veri kaynaklarına dayalıdır. Tıbbi veya hayati kararlar almak için kullanılamaz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Yasal Uyarı")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("tab.settings")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        return version
    }

    @ViewBuilder
    private func dataSourceRow(name: String, description: String, license: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                licenseTag(license, url: url)
            }
            Text(String(localized: String.LocalizationValue(description)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func licenseTag(_ key: String, url: String) -> some View {
        let resolvedLabel: String = {
            switch key {
            case "settings.attribution.publicDomain":
                return "Public Domain"
            case "settings.attribution.academic":
                return "Academic"
            default:
                return key
            }
        }()
        if let dest = URL(string: url) {
            Link(resolvedLabel, destination: dest)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        } else {
            Text(resolvedLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct ActivityManagementView: View {
    @Binding var activities: [Activity]
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section("settings.activities.configured") {
                ForEach($activities) { $activity in
                    NavigationLink(destination: ActivityDetailView(activity: $activity)) {
                        HStack {
                            Text(activity.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            Section {
                Button(action: { showResetAlert = true }) {
                    Text("settings.activities.reset")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("settings.activities.manage")
        .onChange(of: activities) { _, newValue in
            ActivityStorage.saveActivities(newValue)
        }
        .alert("settings.activities.resetConfirm", isPresented: $showResetAlert) {
            Button("common.cancel", role: .cancel) { }
            Button("common.reset", role: .destructive) {
                activities = Activity.defaults
                ActivityStorage.resetToDefaults()
            }
        } message: {
            Text("settings.activities.resetMessage")
        }
    }
}

struct ActivityDetailView: View {
    @Binding var activity: Activity
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("activity.basicInfo") {
                TextField("activity.name", text: $activity.name)

                Stepper(Self.formatted("activity.minTemp.format", activity.minTemperature),
                        value: $activity.minTemperature, in: -50...50, step: 1)

                Stepper(Self.formatted("activity.maxTemp.format", activity.maxTemperature),
                        value: $activity.maxTemperature, in: -50...50, step: 1)
            }

            Section("activity.windConditions") {
                Stepper(Self.formatted("activity.maxWind.format", activity.maxWindSpeed),
                        value: $activity.maxWindSpeed, in: 0...100, step: 1)

                Stepper(Self.formatted("activity.maxGust.format", activity.maxWindGust),
                        value: $activity.maxWindGust, in: 0...150, step: 1)
            }

            Section("activity.otherConditions") {
                Stepper(Self.formatted("activity.minVis.format", activity.minVisibility),
                        value: $activity.minVisibility, in: 0...20, step: 0.5)

                Stepper(Self.formattedInt("activity.maxUV.format", activity.maxUVIndex),
                        value: $activity.maxUVIndex, in: 0...11, step: 1)
            }

            Section("activity.weatherPreferences") {
                Toggle("activity.avoidRain", isOn: $activity.avoidRain)
                Toggle("activity.avoidSnow", isOn: $activity.avoidSnow)
                Toggle("activity.avoidFog", isOn: $activity.avoidFog)
                Toggle("activity.avoidStorm", isOn: $activity.avoidStorm)
            }
        }
        .navigationTitle(activity.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Resolves a `%.1f`-style localized format key and substitutes the value,
    /// so Stepper titles are actually translated instead of showing the raw
    /// "activity.minTemp: 5.0°C" interpolated key to the user.
    private static func formatted(_ key: String, _ value: Double) -> String {
        String(format: String(localized: String.LocalizationValue(key)), value)
    }

    private static func formattedInt(_ key: String, _ value: Int) -> String {
        String(format: String(localized: String.LocalizationValue(key)), value)
    }
}
#endif
