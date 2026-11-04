import Foundation

struct LeaderboardEntry: Codable {
    let id: Int
    let deviceName: String
    let os: String
    /// The server does not send this field.
    let browser: String?
    let avgFPS: Double
    let onePercentLow: Double
    let score: Double
    let tier: String
    let batteryDrain: Double
    let createdAt: String
}
