import Foundation

struct BenchmarkResult: Codable, Equatable {
    let clientResultId: String
    let avgFPS: Double
    let minFPS: Double
    let onePercentLow: Double
    let stability: Double
    let cpuScore: Double
    let gpuScore: Double
    let score: Double
    let tier: Tier
    let batteryDrain: Double
    let batteryEfficiency: Double
    var fpsTimeline: [FPSSample]
    var duration: Double
    var detectedHz: Int
    /// Display only. Never affects the score.
    let effectiveTargetHz: Int
    /// Display only. Never affects the score.
    let is60HzLocked: Bool
    var gpuRenderer: String?
    let retention: Double
    let singleCoreScore: Double
    let multiCoreScore: Double
    let singleCoreWorkUnitsPerSec: Double
    let multiCoreWorkUnitsPerSec: Double
    let cpuCoresUsed: Int
}
