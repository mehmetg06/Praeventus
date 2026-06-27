#if canImport(SwiftUI)
import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif

/// MVVM view model for the inline city-search experience on the Home screen.
///
/// Owns the query lifecycle: debouncing (300 ms), in-flight task cancellation,
/// per-query result caching, and GPS reverse-geocoding. Deliberately decoupled
/// from `WeatherStore` — the View wires the two together on selection.
@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - Published state

    /// The live text bound to the search field.
    @Published var query: String = ""

    /// Geocoding suggestions for the current query.
    @Published private(set) var suggestions: [GeocodingResult] = []

    /// True while a geocoding network request is in-flight.
    @Published private(set) var isSearching: Bool = false

    /// True while the GPS + reverse-geocode flow is running.
    @Published private(set) var isLocating: Bool = false

    /// Non-nil when a search or location error has occurred.
    @Published private(set) var searchError: String? = nil

    /// Controls dropdown visibility. Set to `true` when results arrive;
    /// `false` when the user selects a result, taps away, or clears the query.
    @Published private(set) var isShowingSuggestions: Bool = false

    // MARK: - Private

    private let client: OpenMeteoClient

    #if canImport(CoreLocation)
    private let locator = LocationProvider()
    #endif

    /// Handle to the most recent search task so it can be cancelled on new input.
    private var searchTask: Task<Void, Never>?

    /// In-memory result cache: trimmed-lowercase query → results. Capped to avoid unbounded growth.
    private var cache: [String: [GeocodingResult]] = [:]
    private static let cacheLimit = 100

    init(client: OpenMeteoClient = OpenMeteoClient()) {
        self.client = client
    }

    // MARK: - Query handling

    /// Called whenever the query string changes. Cancels any in-flight request
    /// and starts a new debounced search when the query is long enough.
    func onQueryChanged(_ newQuery: String) {
        searchTask?.cancel()
        searchTask = nil

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            isShowingSuggestions = false
            searchError = nil
            return
        }

        // Serve cached results immediately so the UI feels instant.
        if let cached = cache[trimmed.lowercased()] {
            suggestions = cached
            isShowingSuggestions = !cached.isEmpty
        }

        searchTask = Task {
            await self.fetchSuggestions(trimmed)
        }
    }

    private func fetchSuggestions(_ query: String) async {
        // 300 ms debounce — the task is cancelled if the user keeps typing.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let results = try await client.search(query)
            guard !Task.isCancelled else { return }
            if cache.count >= Self.cacheLimit { cache.removeAll() }
            cache[query.lowercased()] = results
            suggestions = results
            isShowingSuggestions = true
            if results.isEmpty {
                searchError = String(
                    localized: "search.noResults",
                    defaultValue: "No matching places."
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            searchError = String(
                localized: "error.searchFailed",
                defaultValue: "Search failed."
            )
        }
    }

    // MARK: - Dismissal / reset

    func dismissSuggestions() {
        isShowingSuggestions = false
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        suggestions = []
        isShowingSuggestions = false
        searchError = nil
    }

    // MARK: - Current location

    #if canImport(CoreLocation)
    /// Requests a coarse GPS fix, reverse-geocodes it, and returns the result.
    /// Sets `searchError` and returns `nil` on failure.
    func requestCurrentLocation() async -> (latitude: Double, longitude: Double, name: String, country: String)? {
        guard !isLocating else { return nil }
        isLocating = true
        searchError = nil
        defer { isLocating = false }
        do {
            let coordinate = try await locator.requestCoordinate()
            let place = await reverseGeocode(coordinate)
            return (coordinate.latitude, coordinate.longitude, place.name, place.country)
        } catch {
            searchError = String(
                localized: "error.locationDenied",
                defaultValue: "Location is unavailable or permission was denied."
            )
            return nil
        }
    }

    /// Uses Apple's on-device geocoder (no network) to turn a coordinate into a place name.
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
