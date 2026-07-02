import XCTest
@testable import AppModule

/// Regression guard for the backend's `daily.sunrise`/`daily.sunset` strings.
///
/// `deno/astro.ts` builds these via JavaScript's `Date.toISOString()`, which
/// always emits fractional seconds ("2026-07-02T05:12:34.000Z"). Before this
/// fix, `WeatherMapping`'s ISO-8601 parse chain only handled
/// `.withInternetDateTime` (no fractional seconds), so every sunrise/sunset
/// string silently failed to parse and `DailyRange.sunrise`/`.sunset` decoded
/// to `nil` on every real forecast — with nothing surfacing the failure,
/// since nothing in the UI happened to read those fields.
final class WeatherMappingSunriseSunsetTests: XCTestCase {

    func testSunriseSunsetWithFractionalSecondsParse() {
        let response = ForecastResponse(
            latitude: 41.0,
            longitude: 29.0,
            timezone: "Europe/Istanbul",
            elevation: nil,
            current: ForecastResponse.Current(
                time: "2026-07-02T12:00",
                temperature2m: 24, apparentTemperature: 24,
                relativeHumidity2m: 55, surfacePressure: 1013, pressureMsl: 1013,
                windSpeed10m: 10, windDirection10m: 180, windGusts10m: 15,
                precipitationProbability: 5, weatherCode: 0, uvIndex: 6,
                dewPoint2m: 14, visibility: 10000
            ),
            hourly: nil,
            daily: ForecastResponse.Daily(
                time: ["2026-07-02"],
                temperature2mMax: [28], temperature2mMin: [18],
                apparentTemperatureMax: [29], apparentTemperatureMin: [17],
                uvIndexMax: [7], windSpeed10mMax: [20],
                windDirection10mDominant: [180], windGusts10mMax: [30],
                precipitationSum: [0], weatherCode: [0],
                // Real backend shape: JS `toISOString()` always has ".000".
                sunrise: ["2026-07-02T05:12:34.000Z"],
                sunset: ["2026-07-02T19:45:10.000Z"]
            )
        )

        let mapped = WeatherMapping.map(response, city: "Istanbul", country: "Turkey")

        guard let daily = mapped.daily.first else {
            return XCTFail("Expected one DailyRange")
        }
        XCTAssertNotNil(daily.sunrise, "daily.sunrise should parse despite fractional seconds")
        XCTAssertNotNil(daily.sunset, "daily.sunset should parse despite fractional seconds")

        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!

        if let sunrise = daily.sunrise {
            let comps = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: sunrise)
            XCTAssertEqual(comps.hour, 5)
            XCTAssertEqual(comps.minute, 12)
            XCTAssertEqual(comps.second, 34)
        }
        if let sunset = daily.sunset {
            let comps = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: sunset)
            XCTAssertEqual(comps.hour, 19)
            XCTAssertEqual(comps.minute, 45)
            XCTAssertEqual(comps.second, 10)
        }
    }

    /// The pre-existing non-fractional MET Norway/BrightSky shape must keep
    /// working alongside the new fractional-seconds path.
    func testHourlyTimeWithoutFractionalSecondsStillParses() {
        let response = ForecastResponse(
            latitude: 41.0, longitude: 29.0, timezone: nil, elevation: nil,
            current: ForecastResponse.Current(
                time: "2026-07-02T12:00", temperature2m: 24, apparentTemperature: 24,
                relativeHumidity2m: 55, surfacePressure: 1013, pressureMsl: 1013,
                windSpeed10m: 10, windDirection10m: 180, windGusts10m: 15,
                precipitationProbability: 5, weatherCode: 0, uvIndex: 6,
                dewPoint2m: 14, visibility: 10000
            ),
            hourly: ForecastResponse.Hourly(
                time: ["2026-07-02T12:00:00Z"],
                temperature2m: [24], precipitationProbability: [5], weatherCode: [0],
                uvIndex: [6], windSpeed10m: [10], windDirection10m: [180],
                windGusts10m: [15], relativeHumidity2m: [55], dewPoint2m: [14],
                visibility: [10000]
            ),
            daily: nil
        )

        let mapped = WeatherMapping.map(response, city: "Istanbul", country: "Turkey")
        XCTAssertEqual(mapped.hourly.count, 1, "MET Norway/BrightSky-style timestamps without fractional seconds must still parse")
    }
}
