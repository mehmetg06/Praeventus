#if canImport(SwiftUI)
import SwiftUI

struct SettingsView: View {
    @State private var proxyURL: String = WeatherEndpoint.proxyBaseURL ?? ""
    @State private var showActivityEditor = false
    @State private var activities = ActivityStorage.loadActivities()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("settings.proxy.placeholder", text: $proxyURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit(saveProxy)
                    Button("settings.proxy.save", action: saveProxy)
                } header: {
                    Text("settings.proxy.title")
                } footer: {
                    Text("settings.proxy.footer")
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
                    LabeledContent("settings.about.source", value: "Open-Meteo (ECMWF)")
                    LabeledContent("settings.about.version", value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("tab.settings")
        }
    }

    private func saveProxy() {
        WeatherEndpoint.setProxyBaseURL(proxyURL)
        proxyURL = WeatherEndpoint.proxyBaseURL ?? ""
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        return version
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

                Stepper("activity.minTemp: \(String(format: "%.1f", activity.minTemperature))°C",
                        value: $activity.minTemperature, in: -50...50, step: 1)

                Stepper("activity.maxTemp: \(String(format: "%.1f", activity.maxTemperature))°C",
                        value: $activity.maxTemperature, in: -50...50, step: 1)
            }

            Section("activity.windConditions") {
                Stepper("activity.maxWind: \(String(format: "%.1f", activity.maxWindSpeed)) km/h",
                        value: $activity.maxWindSpeed, in: 0...100, step: 1)

                Stepper("activity.maxGust: \(String(format: "%.1f", activity.maxWindGust)) km/h",
                        value: $activity.maxWindGust, in: 0...150, step: 1)
            }

            Section("activity.otherConditions") {
                Stepper("activity.minVis: \(String(format: "%.1f", activity.minVisibility)) km",
                        value: $activity.minVisibility, in: 0...20, step: 0.5)

                Stepper("activity.maxUV: \(activity.maxUVIndex)",
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
}
#endif
