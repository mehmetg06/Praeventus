#if canImport(SwiftUI)
import SwiftUI

struct SettingsView: View {
    @State private var proxyURL: String = WeatherEndpoint.proxyBaseURL ?? ""

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
#endif
