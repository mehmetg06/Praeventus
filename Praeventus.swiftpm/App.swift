#if canImport(SwiftUI)
import SwiftUI

@main
struct PraeventusApp: App {
    var body: some Scene {
        WindowGroup {
            PraeventusRootView()
        }
    }
}
#else
import Foundation

/// CLI entry point used on non-Apple platforms (e.g. Linux CI). It exercises the
/// pure-Foundation data layer end-to-end against the live API so the networking,
/// decoding and WMO→condition mapping can be verified without an iPad.
///
/// Run: `swift run` (from inside `Praeventus.swiftpm`).
@main
struct PraeventusCLI {
    static func main() async {
        print("Praeventus data-layer check — the UI runs in Swift Playgrounds on iPad.")
        let client = OpenMeteoClient()

        do {
            let query = "Tokyo"
            print("\nGeocoding \"\(query)\"…")
            let results = try await client.search(query)
            guard let place = results.first else {
                print("No geocoding results.")
                return
            }
            print("→ \(place.name), \(place.subtitle) (\(place.latitude), \(place.longitude))")

            print("\nFetching forecast…")
            let response = try await client.forecast(latitude: place.latitude, longitude: place.longitude)
            let mapped = WeatherMapping.map(response, city: place.name, country: place.country ?? "")
            let w = mapped.weather
            print("""
            → \(w.city): \(Int(w.temperature.rounded()))°C (feels \(Int(w.feelsLike.rounded()))°C), \
            \(w.condition), humidity \(Int(w.humidity))%, wind \(Int(w.windSpeed)) km/h
            → hourly points: \(mapped.hourly.count), daily ranges: \(mapped.daily.count)
            """)
        } catch {
            print("Data-layer check failed: \(error)")
        }
    }
}
#endif
