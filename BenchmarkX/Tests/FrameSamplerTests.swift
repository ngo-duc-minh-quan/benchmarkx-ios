import XCTest
@testable import BenchmarkX

final class FrameSamplerTests: XCTestCase {
    private var sampler: FrameSampler!
    /// Timestamp of the last completed 500ms window. Multiples of 0.5 are exact in binary.
    private var clock = 1000.0

    override func setUp() {
        super.setUp()
        sampler = FrameSampler()
        sampler.tick(timestamp: clock)
    }

    /// Feeds `fps / 2` evenly spaced frames, the last one landing exactly 500ms after the previous window.
    /// `fps` must be even.
    private func feedWindow(fps: Int) {
        let frames = fps / 2
        for j in 1...frames {
            sampler.tick(timestamp: clock + 0.5 * Double(j) / Double(frames))
        }
        clock += 0.5
    }

    func testFirstFrameOnlyMarksStartAndProducesNoFrameTime() {
        XCTAssertTrue(sampler.frameTimesMs.isEmpty)
        XCTAssertTrue(sampler.fpsArray.isEmpty)
        XCTAssertEqual(sampler.elapsed, 0)
    }

    func testAbnormalFrameTimesAreDropped() {
        sampler.tick(timestamp: 1000.25)   // 250ms: dropped
        sampler.tick(timestamp: 1000.45)   // ~200ms: kept
        sampler.tick(timestamp: 1000.45)   // 0ms: dropped
        sampler.tick(timestamp: 1000.40)   // negative: dropped

        XCTAssertEqual(sampler.frameTimesMs.count, 1)
        XCTAssertEqual(sampler.frameTimesMs[0], 200, accuracy: 0.001)
    }

    func testProducesExactlyOneFPSSampleAfter500ms() {
        feedWindow(fps: 64)

        XCTAssertEqual(sampler.fpsArray, [64])
        XCTAssertEqual(sampler.fpsTimeline.count, 1)
        XCTAssertEqual(sampler.fpsTimeline[0].t, 1)   // round(0.5s) = 1
        XCTAssertEqual(sampler.fpsTimeline[0].fps, 64)
        XCTAssertEqual(sampler.liveFPS, 64)
        XCTAssertEqual(sampler.peakFPS, 64)
        XCTAssertEqual(sampler.minFPS, 64)
        XCTAssertEqual(sampler.elapsed, 0.5, accuracy: 0.0001)
    }

    func testDoesNotSampleBefore500ms() {
        sampler.tick(timestamp: 1000.1)
        sampler.tick(timestamp: 1000.2)
        sampler.tick(timestamp: 1000.4)

        XCTAssertTrue(sampler.fpsArray.isEmpty)
    }

    func testTracksPeakAndMinFPS() {
        feedWindow(fps: 60)
        feedWindow(fps: 100)
        feedWindow(fps: 40)

        XCTAssertEqual(sampler.liveFPS, 40)
        XCTAssertEqual(sampler.peakFPS, 100)
        XCTAssertEqual(sampler.minFPS, 40)
    }

    func testDropOf25PercentAgainstBaselineSetsThrottling() {
        for _ in 0..<10 { feedWindow(fps: 200) }
        XCTAssertFalse(sampler.isThrottling)

        feedWindow(fps: 150)   // 25% below baseline 200

        XCTAssertTrue(sampler.isThrottling)
        XCTAssertEqual(sampler.throttleDropPercent, 25)
    }

    func testDropOf24PercentDoesNotSetThrottling() {
        for _ in 0..<10 { feedWindow(fps: 200) }

        feedWindow(fps: 152)   // 24% below baseline 200

        XCTAssertFalse(sampler.isThrottling)
    }

    func testThrottlingClearsWhenFPSRecovers() {
        for _ in 0..<10 { feedWindow(fps: 200) }
        feedWindow(fps: 100)
        XCTAssertTrue(sampler.isThrottling)

        feedWindow(fps: 200)

        XCTAssertFalse(sampler.isThrottling)
    }

    func testNoThrottlingBeforeBaselineExists() {
        for _ in 0..<8 { feedWindow(fps: 200) }
        feedWindow(fps: 20)   // 9th sample: no baseline yet

        XCTAssertEqual(sampler.fpsArray.count, 9)
        XCTAssertFalse(sampler.isThrottling)
    }

    func testTenthSampleIsAlreadyComparedAgainstItsOwnBaseline() {
        for _ in 0..<9 { feedWindow(fps: 200) }
        feedWindow(fps: 20)   // 10th sample: baseline = avg of 10 = 182

        XCTAssertTrue(sampler.isThrottling)
        XCTAssertEqual(sampler.throttleDropPercent, 89)
    }
}
