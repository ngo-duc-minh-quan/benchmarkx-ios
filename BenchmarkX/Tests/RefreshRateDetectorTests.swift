import XCTest
@testable import BenchmarkX

final class RefreshRateDetectorTests: XCTestCase {
    func testSnapPicksNearestStandardRate() {
        XCTAssertEqual(RefreshRateDetector.snap(59.7), 60)
        XCTAssertEqual(RefreshRateDetector.snap(89), 90)
        XCTAssertEqual(RefreshRateDetector.snap(118), 120)
        XCTAssertEqual(RefreshRateDetector.snap(143), 144)
        XCTAssertEqual(RefreshRateDetector.snap(61), 60)
    }

    func testRawHzFromEvenDeltasMatchesTheRate() {
        let at120 = Array(repeating: 1000.0 / 120, count: 60)
        XCTAssertEqual(RefreshRateDetector.rawHz(fromDeltasMs: at120), 120, accuracy: 0.001)

        let at60 = Array(repeating: 1000.0 / 60, count: 60)
        XCTAssertEqual(RefreshRateDetector.rawHz(fromDeltasMs: at60), 60, accuracy: 0.001)
    }

    func testRawHzUsesMedianSoOutliersDoNotMatter() {
        var deltas = Array(repeating: 1000.0 / 60, count: 57)
        deltas += [100, 120, 250]   // frames lost to an interruption
        XCTAssertEqual(RefreshRateDetector.rawHz(fromDeltasMs: deltas), 60, accuracy: 0.001)
    }

    func testDetectedRateOfEvenDeltasSnapsCorrectly() {
        let deltas = Array(repeating: 1000.0 / 120, count: 60)
        XCTAssertEqual(RefreshRateDetector.snap(RefreshRateDetector.rawHz(fromDeltasMs: deltas)), 120)
    }
}
