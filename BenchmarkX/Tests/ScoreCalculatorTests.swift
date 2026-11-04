import XCTest
@testable import BenchmarkX

final class ScoreCalculatorTests: XCTestCase {
    private func steadyFPS(_ fps: Double, samples: Int = 20) -> [Double] {
        Array(repeating: fps, count: samples)
    }

    private func steadyFrameTimes(_ fps: Double, frames: Int = 600) -> [Double] {
        Array(repeating: 1000 / fps, count: frames)
    }

    private func alternating(_ a: Double, _ b: Double, pairs: Int = 10) -> [Double] {
        (0..<pairs).flatMap { _ in [a, b] }
    }

    func testEmptyInputReturnsZeroScoresAndTierC() {
        let result = ScoreCalculator.calculate(
            fpsArray: [], frameTimesMs: [], batteryDrain: 5, targetHz: 90
        )

        XCTAssertEqual(result.avgFPS, 0)
        XCTAssertEqual(result.minFPS, 0)
        XCTAssertEqual(result.onePercentLow, 0)
        XCTAssertEqual(result.stability, 0)
        XCTAssertEqual(result.cpuScore, 0)
        XCTAssertEqual(result.gpuScore, 0)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.tier, .C)
        XCTAssertEqual(result.retention, 100)
        XCTAssertEqual(result.detectedHz, 60)
        XCTAssertEqual(result.effectiveTargetHz, 90)
        XCTAssertFalse(result.is60HzLocked)
    }

    func testPerfect60FPSWithFullCpuScores100TierS() {
        let result = ScoreCalculator.calculate(
            fpsArray: steadyFPS(60),
            frameTimesMs: steadyFrameTimes(60),
            batteryDrain: 2,
            singleCoreScore: 100,
            multiCoreScore: 100,
            targetHz: 60
        )

        XCTAssertEqual(result.gpuScore, 100, accuracy: 0.0001)
        XCTAssertEqual(result.cpuScore, 100, accuracy: 0.0001)
        XCTAssertEqual(result.score, 100, accuracy: 0.0001)
        XCTAssertEqual(result.tier, .S)
    }

    func testScoreNeverExceeds100At120FPS() {
        let result = ScoreCalculator.calculate(
            fpsArray: steadyFPS(120),
            frameTimesMs: steadyFrameTimes(120),
            batteryDrain: 2,
            singleCoreScore: 100,
            multiCoreScore: 100,
            targetHz: 120
        )

        XCTAssertLessThanOrEqual(result.score, 100)
        XCTAssertLessThanOrEqual(result.gpuScore, 100)
        XCTAssertEqual(result.score, 100, accuracy: 0.0001)
    }

    func testDetects60HzLockOnlyWhenTargetIs90OrMoreAndFPSIsStableNear60() {
        let locked = ScoreCalculator.calculate(
            fpsArray: alternating(58, 62), frameTimesMs: [], batteryDrain: 0, targetHz: 120
        )
        XCTAssertTrue(locked.is60HzLocked)
        XCTAssertEqual(locked.effectiveTargetHz, 60)

        let lowTarget = ScoreCalculator.calculate(
            fpsArray: alternating(58, 62), frameTimesMs: [], batteryDrain: 0, targetHz: 60
        )
        XCTAssertFalse(lowTarget.is60HzLocked)
        XCTAssertEqual(lowTarget.effectiveTargetHz, 60)

        let highFPS = ScoreCalculator.calculate(
            fpsArray: steadyFPS(118), frameTimesMs: [], batteryDrain: 0, targetHz: 120
        )
        XCTAssertFalse(highFPS.is60HzLocked)
        XCTAssertEqual(highFPS.effectiveTargetHz, 120)

        let unstable = ScoreCalculator.calculate(
            fpsArray: alternating(40, 80), frameTimesMs: [], batteryDrain: 0, targetHz: 120
        )
        XCTAssertFalse(unstable.is60HzLocked)
    }

    func testLockDoesNotChangeScoreBetweenTargetHz60And120() {
        let fps = alternating(58, 62)
        let at60 = ScoreCalculator.calculate(
            fpsArray: fps, frameTimesMs: [], batteryDrain: 3, targetHz: 60
        )
        let at120 = ScoreCalculator.calculate(
            fpsArray: fps, frameTimesMs: [], batteryDrain: 3, targetHz: 120
        )

        XCTAssertFalse(at60.is60HzLocked)
        XCTAssertTrue(at120.is60HzLocked)
        XCTAssertEqual(at60.gpuScore, at120.gpuScore)
        XCTAssertEqual(at60.score, at120.score)
        XCTAssertEqual(at60.tier, at120.tier)
    }

    func testTierThresholdsIncludingBoundaries() {
        XCTAssertEqual(ScoreCalculator.classifyTier(100), .S)
        XCTAssertEqual(ScoreCalculator.classifyTier(85), .S)
        XCTAssertEqual(ScoreCalculator.classifyTier(84.9), .A)
        XCTAssertEqual(ScoreCalculator.classifyTier(70), .A)
        XCTAssertEqual(ScoreCalculator.classifyTier(69.9), .B)
        XCTAssertEqual(ScoreCalculator.classifyTier(55), .B)
        XCTAssertEqual(ScoreCalculator.classifyTier(54.9), .C)
        XCTAssertEqual(ScoreCalculator.classifyTier(0), .C)
    }

    func testCombinedCpuScoreIs40PercentSingleAnd60PercentMulti() {
        let result = ScoreCalculator.calculate(
            fpsArray: steadyFPS(60),
            frameTimesMs: [],
            batteryDrain: 0,
            singleCoreScore: 50,
            multiCoreScore: 100
        )

        XCTAssertEqual(result.cpuScore, 80, accuracy: 0.0001)
    }

    func testRetentionDropsWhenFPSDeclines() {
        // 20 samples -> window of 3. First 3 avg 58.5, last 3 avg 33 -> 56.4%.
        let declining = (0..<20).map { 60 - Double($0) * 1.5 }
        let result = ScoreCalculator.calculate(
            fpsArray: declining, frameTimesMs: [], batteryDrain: 0, targetHz: 60
        )

        XCTAssertEqual(result.retention, 56.4, accuracy: 0.05)

        let steady = ScoreCalculator.calculate(
            fpsArray: steadyFPS(60), frameTimesMs: [], batteryDrain: 0, targetHz: 60
        )
        XCTAssertEqual(steady.retention, 100, accuracy: 0.0001)
    }
}
