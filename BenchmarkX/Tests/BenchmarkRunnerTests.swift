import XCTest
@testable import BenchmarkX

final class BenchmarkRunnerTests: XCTestCase {
    // MARK: - Battery

    func testInitialBatteryUsesTheRealLevelWhenSupported() {
        let battery = BenchmarkRunner.initialBattery(level: 0.5)

        XCTAssertEqual(battery.percent, 50, accuracy: 0.0001)
        XCTAssertTrue(battery.supported)
    }

    func testInitialBatteryIs100AndUnsupportedWhenLevelIsUnknown() {
        let battery = BenchmarkRunner.initialBattery(level: -1)

        XCTAssertEqual(battery.percent, 100)
        XCTAssertFalse(battery.supported)
    }

    func testBatteryDrainIsRoundedToTwoDecimals() {
        // 100% -> 92.34% is a drain of 7.66 points.
        let drain = BenchmarkRunner.batteryDrain(startPercent: 100, endLevel: 0.9234, supported: true)

        XCTAssertEqual(drain, 7.66, accuracy: 1e-9)
    }

    func testBatteryDrainIsNeverNegativeWhenBatteryRises() {
        let drain = BenchmarkRunner.batteryDrain(startPercent: 50, endLevel: 0.6, supported: true)

        XCTAssertEqual(drain, 0)
    }

    func testBatteryDrainBelowOnePercentKeepsTheRealValue() {
        let drain = BenchmarkRunner.batteryDrain(startPercent: 80, endLevel: 0.795, supported: true)

        XCTAssertEqual(drain, 0.5, accuracy: 1e-9)
    }

    func testBatteryDrainIsZeroWhenUnsupported() {
        // An unknown end level (-1) must not turn into a 200 point drain.
        XCTAssertEqual(BenchmarkRunner.batteryDrain(startPercent: 100, endLevel: -1, supported: false), 0)
        XCTAssertEqual(BenchmarkRunner.batteryDrain(startPercent: 100, endLevel: 0.5, supported: false), 0)
        XCTAssertEqual(BenchmarkRunner.batteryDrain(startPercent: 80, endLevel: -1, supported: true), 0)
    }

    // MARK: - Multi-core fallback

    func testMultiCoreScoreFallsBackToSingleCoreWhenNoWorkWasDone() {
        let multi = CPUBenchmarkResult(workUnits: 0, durationMs: 3000, score: 0, workUnitsPerSec: 0)

        XCTAssertEqual(BenchmarkRunner.multiCoreScore(multi: multi, singleCoreScore: 42.5), 42.5)
    }

    func testMultiCoreScoreIsKeptWhenWorkWasDone() {
        let multi = CPUBenchmarkResult(workUnits: 300, durationMs: 3000, score: 71.3, workUnitsPerSec: 100)

        XCTAssertEqual(BenchmarkRunner.multiCoreScore(multi: multi, singleCoreScore: 42.5), 71.3)
    }
}
