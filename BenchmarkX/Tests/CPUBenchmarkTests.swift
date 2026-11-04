import XCTest
@testable import BenchmarkX

final class CPUBenchmarkTests: XCTestCase {
    func testPrimeSieveFindsTwentyFivePrimesBelow100() {
        XCTAssertEqual(CPUBenchmark.primeSieve(limit: 100), 25)
    }

    func testMatMulIsDeterministic() {
        XCTAssertEqual(CPUBenchmark.matMul(size: 10), CPUBenchmark.matMul(size: 10))
    }

    func testMatMulReturnsSumOfAllElements() {
        // Sum of the whole 3x3 result matrix (reference computed independently).
        XCTAssertEqual(CPUBenchmark.matMul(size: 3), 4.6222, accuracy: 1e-9)
    }

    func testMatMulSize100IsNotZero() {
        // c[0] is always 0 for size 100, so the checksum must cover the whole matrix.
        XCTAssertNotEqual(CPUBenchmark.matMul(size: 100), 0)
    }

    func testNormalizeSingleCoreCapsAt100() {
        // 400 WU in 1s = 400 WU/s, baseline 40 -> 1000%, capped.
        XCTAssertEqual(CPUBenchmark.normalizeSingleCore(workUnits: 400, durationMs: 1000), 100)
        // 20 WU in 1s = 50% of baseline.
        XCTAssertEqual(CPUBenchmark.normalizeSingleCore(workUnits: 20, durationMs: 1000), 50)
    }

    func testNormalizeMultiCoreScalesBaselineBy70PercentPerCore() {
        // 6 cores -> scaling 4.2 -> target 168 WU/s. 84 WU/s -> 50.
        XCTAssertEqual(
            CPUBenchmark.normalizeMultiCore(workUnits: 84, durationMs: 1000, cores: 6),
            50,
            accuracy: 0.0001
        )
    }
}
