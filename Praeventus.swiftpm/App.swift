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
/// pure-Foundation data layer end-to-end against the Cloudflare Worker so the
/// networking, decoding, fusion and WMO→condition mapping can be verified
/// without an iPad.
///
/// Run: `swift run` (from inside `Praeventus.swiftpm`).
@main
struct PraeventusCLI {
    static func main() async {
        print("Praeventus data-layer check — the UI runs in Swift Playgrounds on iPad.")
        let cf = CloudflareWeatherProvider(baseURL: WeatherSettings.cloudflareWorkerURL)

        do {
            let query = "Tokyo"
            print("\nGeocoding \"\(query)\"…")
            let results = try await cf.search(query)
            guard let place = results.first else {
                print("No geocoding results.")
                return
            }
            print("→ \(place.name), \(place.subtitle) (\(place.latitude), \(place.longitude))")

            print("\nFetching forecast via Cloudflare Worker…")
            let keyed = try await cf.forecast(latitude: place.latitude, longitude: place.longitude)
            let fused = WeatherFusion.fuse(keyed)
            let mapped = WeatherMapping.map(fused.response, city: place.name, country: place.country ?? "")
            let w = mapped.weather
            print("""
            → \(w.city): \(Int(w.temperature.rounded()))°C (feels \(Int(w.feelsLike.rounded()))°C), \
            \(w.condition), humidity \(Int(w.humidity))%, wind \(Int(w.windSpeed)) km/h
            → hourly points: \(mapped.hourly.count), daily ranges: \(mapped.daily.count)
            → models: \(keyed.count)/\(WeatherModel.fusionSet.count) \
            (\(fused.confidence.models.joined(separator: ", ")))
            → agreement \(fused.confidence.agreementPercent)% (spread \(String(format: "%.1f", fused.confidence.temperatureSpreadC))°C)
            """)
        } catch {
            print("Data-layer check failed: \(error)")
        }
    }
}
#endif
