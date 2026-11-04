import Foundation

/// JSON keys must match what the Next.js server reads.
struct SaveResultPayload: Codable {
    let clientResultId: String
    let deviceName: String
    let os: String
    let browser: String
    let cpuCores: Int
    let ramGB: Double
    let gpuRenderer: String
    let avgFPS: Double
    let minFPS: Double
    let onePercentLow: Double
    let cpuScore: Double
    let gpuScore: Double
    let score: Double
    let tier: Tier
    let batteryDrain: Double
    let fpsTimeline: [FPSSample]
    let is60HzLocked: Bool?
    let effectiveTargetHz: Int?
    let singleCoreWorkUnitsPerSec: Double?
    let multiCoreWorkUnitsPerSec: Double?
}
