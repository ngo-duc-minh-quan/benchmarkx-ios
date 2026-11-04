import XCTest
@testable import BenchmarkX

final class CPUBenchmarkTests: XCTestCase {
    func testPrimeSieveFindsTwentyFivePrimesBelow100() {
        XCTAssertEqual(CPUBenchmark.primeSieve(limit: 100), 25)
    }

    func testMatMulIsDeterministic() {
        // c[0] = a[1]*b[3] + a[2]*b[6] = 0.17*0.93 + 0.34*0.86
        XCTAssertEqual(CPUBenchmark.matMul(size: 3), 0.4505, accuracy: 1e-9)
        XCTAssertEqual(CPUBenchmark.matMul(size: 3), CPUBenchmark.matMul(size: 3))
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
