import Foundation

enum ScoreCalculator {
    /// Fixed reference FPS for scoring, independent of the display refresh rate.
    private static let commonTargetFPS = 60.0

    static func calculate(
        fpsArray: [Double],
        frameTimesMs: [Double],
        batteryDrain: Double,
        singleCoreScore: Double = 0,
        multiCoreScore: Double = 0,
        targetHz: Int = 120,
        singleCoreWups: Double = 0,
        multiCoreWups: Double = 0,
        cpuCoresUsed: Int = 0,
        clientResultId: String = UUID().uuidString
    ) -> BenchmarkResult {
        if fpsArray.isEmpty && frameTimesMs.isEmpty {
            return BenchmarkResult(
                clientResultId: clientResultId,
                avgFPS: 0, minFPS: 0, onePercentLow: 0, stability: 0,
                cpuScore: 0, gpuScore: 0, score: 0, tier: .C,
                batteryDrain: 0, batteryEfficiency: 0,
                fpsTimeline: [], duration: 0, detectedHz: 60,
                effectiveTargetHz: targetHz,
                is60HzLocked: false,
                gpuRenderer: nil,
                retention: 100,
                singleCoreScore: 0, multiCoreScore: 0,
                singleCoreWorkUnitsPerSec: 0, multiCoreWorkUnitsPerSec: 0,
                cpuCoresUsed: 0
            )
        }

        let validFrameTimes = frameTimesMs.filter { $0.isFinite && $0 > 0 }

        var avg = 0.0
        var minFPS = 0.0
        var onePercentLow = 0.0
        var stability = 0.0

        if !validFrameTimes.isEmpty {
            let avgFrameTime = mean(validFrameTimes)
            avg = 1000 / avgFrameTime
            minFPS = 1000 / validFrameTimes.max()!

            let worstFrameTimes = validFrameTimes.sorted(by: >)
            let worstCount = max(1, Int((Double(worstFrameTimes.count) * 0.01).rounded(.up)))
            onePercentLow = 1000 / mean(Array(worstFrameTimes.prefix(worstCount)))

            let sd = standardDeviation(validFrameTimes, mean: avgFrameTime)
            stability = clamp(100 * (1 - sd / max(avgFrameTime, 0.001)), 0, 100)
        } else if !fpsArray.isEmpty {
            avg = mean(fpsArray)
            let sorted = fpsArray.sorted()
            minFPS = sorted[0]
            let onePercentCount = max(1, Int((Double(fpsArray.count) * 0.01).rounded(.down)))
            onePercentLow = mean(Array(sorted.prefix(onePercentCount)))

            let sd = standardDeviation(fpsArray, mean: avg)
            stability = clamp(100 * (1 - sd / max(avg, 1)), 0, 100)
        }

        var retention = 100.0
        if fpsArray.count >= 10 {
            let sampleSize = max(2, Int((Double(fpsArray.count) * 0.15).rounded(.down)))
            let firstAvg = mean(Array(fpsArray.prefix(sampleSize)))
            let lastAvg = mean(Array(fpsArray.suffix(sampleSize)))
            if firstAvg > 0 {
                retention = clamp(lastAvg / firstAvg * 100, 0, 100)
            }
        }

        let is60HzLocked = detect60HzLock(fpsArray: fpsArray, targetHz: targetHz)
        let effectiveTargetHz = is60HzLocked ? 60 : targetHz

        let perfScore = min(100, avg / commonTargetFPS * 100)
        let lowScore = min(100, onePercentLow / commonTargetFPS * 100)
        let gpuScore = min(
            100,
            perfScore * 0.55 + lowScore * 0.25 + stability * 0.10 + retention * 0.10
        )

        let combinedCpuScore = round1(singleCoreScore * 0.4 + multiCoreScore * 0.6)
        let cpuScore = min(100, combinedCpuScore)

        let totalScore = min(100, gpuScore * 0.65 + cpuScore * 0.35)
        let batteryEfficiency = batteryDrain > 0 ? avg / batteryDrain : 0

        return BenchmarkResult(
            clientResultId: clientResultId,
            avgFPS: round1(avg),
            minFPS: round1(minFPS),
            onePercentLow: round1(onePercentLow),
            stability: round1(stability),
            cpuScore: round1(cpuScore),
            gpuScore: round1(gpuScore),
            score: round1(totalScore),
            tier: classifyTier(totalScore),
            batteryDrain: batteryDrain,
            batteryEfficiency: round1(batteryEfficiency),
            fpsTimeline: [],
            duration: 0,
            detectedHz: 60,
            effectiveTargetHz: effectiveTargetHz,
            is60HzLocked: is60HzLocked,
            gpuRenderer: nil,
            retention: round1(retention),
            singleCoreScore: round1(singleCoreScore),
            multiCoreScore: round1(multiCoreScore),
            singleCoreWorkUnitsPerSec: round1(singleCoreWups),
            multiCoreWorkUnitsPerSec: round1(multiCoreWups),
            cpuCoresUsed: cpuCoresUsed
        )
    }

    static func classifyTier(_ score: Double) -> Tier {
        if score >= 85 { return .S }
        if score >= 70 { return .A }
        if score >= 55 { return .B }
        return .C
    }

    /// Display-only detection. Must never feed into the score.
    private static func detect60HzLock(fpsArray: [Double], targetHz: Int) -> Bool {
        guard targetHz >= 90, !fpsArray.isEmpty else { return false }
        let avg = mean(fpsArray)
        return avg >= 55 && avg <= 67 && standardDeviation(fpsArray, mean: avg) <= 8
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    /// Population standard deviation (divides by N).
    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return variance.squareRoot()
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
