import XCTest
@testable import AppModule

/// Phase A verification for `SkillTracker`. Focused on the property that
/// matters most for a "safety net" system: it must be a *silent observer* —
/// depositing/verifying skill data must never change what `WeatherFusion`
/// hands back to the rest of the app.
final class SkillTrackerTests: XCTestCase {

    // MARK: - 1. Silent observer: fuse() output is unaffected by SkillTracker

    /// Fuses the same two-model input twice — once with a completely empty
    /// `SkillTracker`, once after driving a busy tracker (deposits, verifies,
    /// ring-buffer overflow) through many rounds — and asserts the fused
    /// `ForecastResponse`/`FusionConfidence` are bit-for-bit identical.
    /// `WeatherFusion.fuse` never reads `SkillTracker` state, so this also
    /// documents that invariant as a regression guard.
    func testSkillTrackerNeverAffectsFusionOutput() async {
        let models = Self.sampleModels()
        let groundTruth = FusionGroundTruth(
            temperatureC: 21, windSpeedKmh: 12, windDirectionDeg: 180,
            pressureHPa: 1015, ageMinutes: 5
        )

        let before = WeatherFusion.fuse(models, groundTruth: groundTruth)

        let tracker = SkillTracker(persistToDisk: false)
        for i in 0..<50 {
            let now = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 300)
            await tracker.deposit(WeatherFusion.receipts(from: models, issuedAt: now))
            await tracker.verify(against: groundTruth, at: now)
        }
        _ = await tracker.snapshot()

        let after = WeatherFusion.fuse(models, groundTruth: groundTruth)

        XCTAssertEqual(before.response, after.response)
        XCTAssertEqual(before.confidence, after.confidence)
    }

    // MARK: - 2. Synthetic bias: a consistently-wrong model scores worse

    /// ECMWF is always +2°C off; ICON is always exact. After 40 verification
    /// rounds, ECMWF's temperature EWMA error must be worse (higher) than
    /// ICON's in the same lead-time bucket.
    func testConsistentlyBiasedModelScoresWorse() async {
        let tracker = SkillTracker(persistToDisk: false)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 0..<40 {
            let now = start.addingTimeInterval(Double(i) * 3600)
            await tracker.deposit([
                ForecastReceipt(model: "ecmwf_ifs025", issuedAt: now, validAt: now,
                                 temperatureC: 22, windSpeedKmh: 10, pressureHPa: 1013),
                ForecastReceipt(model: "icon_global", issuedAt: now, validAt: now,
                                 temperatureC: 20, windSpeedKmh: 10, pressureHPa: 1013)
            ])
            let truth = FusionGroundTruth(
                temperatureC: 20, windSpeedKmh: 10, windDirectionDeg: nil,
                pressureHPa: 1013, ageMinutes: 0
            )
            await tracker.verify(against: truth, at: now)
        }

        let skill = await tracker.snapshot()
        let ecmwfKey = SkillKey(model: "ecmwf_ifs025", variable: .temperature, leadBucket: .shortRange)
        let iconKey = SkillKey(model: "icon_global", variable: .temperature, leadBucket: .shortRange)

        guard let ecmwf = skill[ecmwfKey], let icon = skill[iconKey] else {
            XCTFail("Expected skill entries for both models"); return
        }
        XCTAssertEqual(ecmwf.verificationCount, 40)
        XCTAssertEqual(icon.verificationCount, 40)
        XCTAssertGreaterThan(ecmwf.ewmaError, icon.ewmaError)
        XCTAssertEqual(ecmwf.ewmaError, 2.0, accuracy: 0.01)
        XCTAssertEqual(icon.ewmaError, 0.0, accuracy: 0.01)
    }

    // MARK: - 3. Ring buffer overflow

    /// Depositing more than the 200-slot cap in one call must retain exactly
    /// the newest 200 and drop the oldest first (FIFO).
    func testRingBufferDropsOldestOnOverflow() async {
        let tracker = SkillTracker(persistToDisk: false)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 250 uniquely-identifiable receipts (windSpeedKmh doubles as an index tag).
        let receipts = (0..<250).map { i in
            ForecastReceipt(
                model: "ecmwf_ifs025",
                issuedAt: base, validAt: base.addingTimeInterval(Double(i) * 60),
                temperatureC: 20, windSpeedKmh: Double(i), pressureHPa: 1013
            )
        }
        await tracker.deposit(receipts)

        let remaining = await tracker.receipts
        XCTAssertEqual(remaining.count, 200)
        // The oldest 50 (indices 0...49) must have been dropped.
        XCTAssertEqual(remaining.first?.windSpeedKmh, 50)
        XCTAssertEqual(remaining.last?.windSpeedKmh, 249)
    }

    /// Overflow spread across multiple calls behaves the same as one big call.
    func testRingBufferDropsOldestAcrossMultipleDeposits() async {
        let tracker = SkillTracker(persistToDisk: false)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for batch in 0..<25 {
            let receipts = (0..<10).map { j -> ForecastReceipt in
                let i = batch * 10 + j
                return ForecastReceipt(
                    model: "icon_global",
                    issuedAt: base, validAt: base.addingTimeInterval(Double(i) * 60),
                    temperatureC: 20, windSpeedKmh: Double(i), pressureHPa: 1013
                )
            }
            await tracker.deposit(receipts)
        }

        let remaining = await tracker.receipts
        XCTAssertEqual(remaining.count, 200)
        XCTAssertEqual(remaining.first?.windSpeedKmh, 50)
        XCTAssertEqual(remaining.last?.windSpeedKmh, 249)
    }

    // MARK: - 4. Verify only matches the ±30 min window

    /// Only receipts whose `validAt` is within ±30 min of `now` are scored
    /// and removed; everything else stays buffered untouched.
    func testVerifyOnlyConsumesReceiptsInsideThirtyMinuteWindow() async {
        let tracker = SkillTracker(persistToDisk: false)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let outOfWindowPast   = now.addingTimeInterval(-40 * 60)
        let inWindowPast      = now.addingTimeInterval(-10 * 60)
        let inWindowFuture    = now.addingTimeInterval(10 * 60)
        let outOfWindowFuture = now.addingTimeInterval(40 * 60)

        func receipt(_ validAt: Date, tag: Double) -> ForecastReceipt {
            ForecastReceipt(model: "ecmwf_ifs025", issuedAt: now, validAt: validAt,
                             temperatureC: 20, windSpeedKmh: tag, pressureHPa: 1013)
        }

        await tracker.deposit([
            receipt(outOfWindowPast, tag: 1),
            receipt(inWindowPast, tag: 2),
            receipt(inWindowFuture, tag: 3),
            receipt(outOfWindowFuture, tag: 4)
        ])

        let truth = FusionGroundTruth(
            temperatureC: 20, windSpeedKmh: 10, windDirectionDeg: nil,
            pressureHPa: 1013, ageMinutes: 0
        )
        await tracker.verify(against: truth, at: now)

        let remaining = await tracker.receipts
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(Set(remaining.compactMap(\.windSpeedKmh)), Set([1.0, 4.0]))

        let skill = await tracker.snapshot()
        let key = SkillKey(model: "ecmwf_ifs025", variable: .temperature, leadBucket: .shortRange)
        XCTAssertEqual(skill[key]?.verificationCount, 2)
    }

    // MARK: - 5. Persistence round-trip

    /// Simulates an app relaunch: a second `SkillTracker` instance pointed at
    /// the same file must load the exact receipts + skill table the first
    /// instance wrote.
    func testStateSurvivesReinitFromDisk() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skilltracker_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let trackerA = SkillTracker(persistToDisk: true, fileURL: tempURL)
        await trackerA.deposit([
            ForecastReceipt(model: "ecmwf_ifs025", issuedAt: now, validAt: now.addingTimeInterval(3600),
                             temperatureC: 18, windSpeedKmh: 8, pressureHPa: 1010)
        ])
        await trackerA.verify(
            against: FusionGroundTruth(temperatureC: 20, windSpeedKmh: 8, windDirectionDeg: nil,
                                        pressureHPa: 1010, ageMinutes: 0),
            at: now.addingTimeInterval(3600)
        )

        let receiptsA = await trackerA.receipts
        let skillA = await trackerA.snapshot()
        XCTAssertTrue(receiptsA.isEmpty, "the one receipt should have been verified and removed")
        XCTAssertFalse(skillA.isEmpty)

        // Fresh instance, same file — simulates the app relaunching.
        let trackerB = SkillTracker(persistToDisk: true, fileURL: tempURL)
        let receiptsB = await trackerB.receipts
        let skillB = await trackerB.snapshot()

        XCTAssertEqual(receiptsB, receiptsA)
        XCTAssertEqual(skillB, skillA)
    }

    // MARK: - 6. Concurrency: many overlapping deposits never corrupt state

    /// Fires 50 concurrent `deposit()` calls (5 receipts each = 250 total)
    /// at one actor instance. Actor isolation must serialize them so the
    /// final buffer is exactly the 200-slot cap — no crash, no lost/duplicated
    /// accounting from a data race.
    func testConcurrentDepositsAreSerializedSafely() async {
        let tracker = SkillTracker(persistToDisk: false)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        await withTaskGroup(of: Void.self) { group in
            for batch in 0..<50 {
                group.addTask {
                    let receipts = (0..<5).map { j -> ForecastReceipt in
                        let i = batch * 5 + j
                        return ForecastReceipt(
                            model: "icon_global",
                            issuedAt: base, validAt: base.addingTimeInterval(Double(i) * 60),
                            temperatureC: 20, windSpeedKmh: Double(i), pressureHPa: 1013
                        )
                    }
                    await tracker.deposit(receipts)
                }
            }
        }

        let remaining = await tracker.receipts
        XCTAssertEqual(remaining.count, 200)
    }

    // MARK: - Fixtures

    private static func sampleModels() -> [WeatherModel: ForecastResponse] {
        func hourly(base: Double) -> ForecastResponse.Hourly {
            let times: [String] = (0..<72).map { i in
                let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 3600)
                return ISO8601DateFormatter().string(from: date)
            }
            let temps: [Double?] = (0..<72).map { base + Double($0) * 0.05 }
            let tens: [Double?] = (0..<72).map { _ in 10.0 }
            let codes: [Int?] = (0..<72).map { _ in 1 }
            let uvs: [Double?] = (0..<72).map { _ in 3.0 }
            let dirs: [Double?] = (0..<72).map { _ in 180.0 }
            let gusts: [Double?] = (0..<72).map { _ in 15.0 }
            let humidity: [Double?] = (0..<72).map { _ in 60.0 }
            let dew: [Double?] = (0..<72).map { _ in 12.0 }
            let vis: [Double?] = (0..<72).map { _ in 10000.0 }
            return ForecastResponse.Hourly(
                time: times,
                temperature2m: temps,
                precipitationProbability: tens,
                weatherCode: codes,
                uvIndex: uvs,
                windSpeed10m: tens,
                windDirection10m: dirs,
                windGusts10m: gusts,
                relativeHumidity2m: humidity,
                dewPoint2m: dew,
                visibility: vis
            )
        }
        func response(base: Double) -> ForecastResponse {
            ForecastResponse(
                latitude: 41.0, longitude: 29.0, timezone: "Europe/Istanbul", elevation: 100,
                current: ForecastResponse.Current(
                    time: "2026-06-30T12:00", temperature2m: base, apparentTemperature: base,
                    relativeHumidity2m: 60, surfacePressure: 1013, pressureMsl: 1013,
                    windSpeed10m: 10, windDirection10m: 180, windGusts10m: 15,
                    precipitationProbability: 10, weatherCode: 1, uvIndex: 3,
                    dewPoint2m: 12, visibility: 10000
                ),
                hourly: hourly(base: base),
                daily: nil
            )
        }
        return [
            .ecmwf: response(base: 20),
            .icon: response(base: 22)
        ]
    }
}
