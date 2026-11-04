import Foundation

struct CPUBenchmarkResult {
    let workUnits: Int
    let durationMs: Double
    let score: Double
    let workUnitsPerSec: Double
}

/// 1 Work Unit = 1x primeSieve(500_000) + 1x matMul(100).
/// `runSingleCore` and `runMultiCore` block the calling thread: call them from a background queue.
enum CPUBenchmark {
    // TODO: calibrate. This baseline comes from the JS (React Native) build.
    // Native Swift is much faster, so measure on iPhone 11 before trusting the scores.
    static let provisionalSingleCoreBaseline = 40.0

    static func normalizeSingleCore(workUnits: Int, durationMs: Double) -> Double {
        let workUnitsPerSec = Double(workUnits) / (durationMs / 1000)
        let score = min(100, workUnitsPerSec / provisionalSingleCoreBaseline * 100)
        return round1(score)
    }

    static func normalizeMultiCore(workUnits: Int, durationMs: Double, cores: Int) -> Double {
        let workUnitsPerSec = Double(workUnits) / (durationMs / 1000)
        let scalingFactor = max(1, Double(cores) * 0.7)
        let target = provisionalSingleCoreBaseline * scalingFactor
        let score = min(100, workUnitsPerSec / target * 100)
        return round1(score)
    }

    static func runSingleCore(durationMs: Double = 3000) -> CPUBenchmarkResult {
        let start = nowMs()
        let end = start + durationMs

        var workUnits = 0
        var checksum = 0.0
        while nowMs() < end {
            checksum += runWorkUnit()
            workUnits += 1
        }
        let elapsed = nowMs() - start

        // Consume the checksum so the optimizer cannot discard the work.
        precondition(checksum.isFinite)

        return makeResult(
            workUnits: workUnits,
            elapsed: elapsed,
            score: normalizeSingleCore(workUnits: workUnits, durationMs: elapsed)
        )
    }

    static func runMultiCore(
        cores: Int = ProcessInfo.processInfo.activeProcessorCount,
        durationMs: Double = 3000
    ) -> CPUBenchmarkResult {
        let lock = NSLock()
        var totalWorkUnits = 0
        var totalChecksum = 0.0

        let start = nowMs()
        let end = start + durationMs

        DispatchQueue.concurrentPerform(iterations: cores) { _ in
            var workUnits = 0
            var checksum = 0.0
            while nowMs() < end {
                checksum += runWorkUnit()
                workUnits += 1
            }

            lock.lock()
            totalWorkUnits += workUnits
            totalChecksum += checksum
            lock.unlock()
        }
        let elapsed = nowMs() - start

        precondition(totalChecksum.isFinite)

        return makeResult(
            workUnits: totalWorkUnits,
            elapsed: elapsed,
            score: normalizeMultiCore(workUnits: totalWorkUnits, durationMs: elapsed, cores: cores)
        )
    }

    /// Sieve of Eratosthenes. Returns the count of primes in 0...limit.
    static func primeSieve(limit: Int) -> Int {
        var sieve = [UInt8](repeating: 1, count: limit + 1)
        sieve[0] = 0
        sieve[1] = 0

        var i = 2
        while i * i <= limit {
            if sieve[i] == 1 {
                var j = i * i
                while j <= limit {
                    sieve[j] = 0
                    j += i
                }
            }
            i += 1
        }

        var count = 0
        for n in 2...limit where sieve[n] == 1 {
            count += 1
        }
        return count
    }

    /// size x size matrix multiplication (i-k-j loop) on deterministic data.
    /// Returns the sum of every element of the result. Returning only c[0] would let the
    /// optimizer drop the other elements, and c[0] is always 0 when size is 100.
    static func matMul(size: Int) -> Double {
        let n = size * size
        var a = [Double](repeating: 0, count: n)
        var b = [Double](repeating: 0, count: n)
        var c = [Double](repeating: 0, count: n)

        for i in 0..<n {
            a[i] = Double((i * 17) % 100) / 100
            b[i] = Double((i * 31) % 100) / 100
        }

        for i in 0..<size {
            for k in 0..<size {
                let aik = a[i * size + k]
                for j in 0..<size {
                    c[i * size + j] += aik * b[k * size + j]
                }
            }
        }
        return c.reduce(0, +)
    }

    private static func runWorkUnit() -> Double {
        Double(primeSieve(limit: 500_000)) + matMul(size: 100)
    }

    private static func makeResult(workUnits: Int, elapsed: Double, score: Double) -> CPUBenchmarkResult {
        CPUBenchmarkResult(
            workUnits: workUnits,
            durationMs: elapsed,
            score: score,
            workUnitsPerSec: Double(workUnits) / (elapsed / 1000)
        )
    }

    /// Monotonic clock in milliseconds.
    private static func nowMs() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
