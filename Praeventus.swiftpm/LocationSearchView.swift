#if canImport(SwiftUI)
import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif

/// City search + "use my location" entry point. This is the path that makes the
/// app usable for *anyone, anywhere* — with or without granting GPS access.
struct LocationSearchView: View {
    @ObservedObject var store: WeatherStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var searching = false
    @State private var errorText: String?

    #if canImport(CoreLocation)
    @StateObject private var locator = LocationProvider()
    @State private var locating = false
    #endif

    private let client = OpenMeteoClient()

    var body: some View {
        NavigationStack {
            List {
                #if canImport(CoreLocation)
                Section {
                    Button(action: { Task { await useMyLocation() } }) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                            Text("search.useMyLocation")
                            Spacer()
                            if locating { ProgressView() }
                        }
                    }
                    .disabled(locating)
                } footer: {
                    Text("search.privacyNote")
                }
                #endif

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }

                if searching {
                    Section { HStack { ProgressView(); Text("search.searching") } }
                } else if !results.isEmpty {
                    Section("search.results") {
                        ForEach(results) { result in
                            Button(action: { Task { await choose(result) } }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.body)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section { Text("search.noResults").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("search.title")
            .searchable(text: $query, prompt: Text("search.prompt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .task(id: query) { await runSearch() }
        }
    }

    // MARK: - Actions

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        // Light debounce so we don't fire on every keystroke.
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }

        searching = true
        errorText = nil
        defer { searching = false }
        do {
            results = try await client.search(trimmed)
        } catch {
            if !Task.isCancelled { errorText = String(localized: "error.searchFailed", defaultValue: "Search failed.") }
        }
    }

    private func choose(_ result: GeocodingResult) async {
        await store.load(
            latitude: result.latitude,
            longitude: result.longitude,
            name: result.name,
            country: result.country ?? ""
        )
        dismiss()
    }

    #if canImport(CoreLocation)
    private func useMyLocation() async {
        locating = true
        errorText = nil
        defer { locating = false }
        do {
            let coordinate = try await locator.requestCoordinate()
            let place = await reverseGeocode(coordinate)
            await store.load(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                name: place.name,
                country: place.country
            )
            dismiss()
        } catch {
            errorText = String(localized: "error.locationDenied", defaultValue: "Location is unavailable or permission was denied.")
        }
    }

    /// Apple's on-device geocoder turns the coarse coordinate into a place name.
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> (name: String, country: String) {
        let fallback = String(localized: "location.current", defaultValue: "My Location")
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return (fallback, "")
        }
        let name = placemark.locality ?? placemark.administrativeArea ?? placemark.name ?? fallback
        return (name, placemark.country ?? "")
    }
    #endif
}
#endif
