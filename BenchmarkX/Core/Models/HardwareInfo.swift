import Foundation

struct HardwareInfo {
    let deviceName: String
    let os: String
    let cpuCores: Int
    let ramGB: Double
    let socName: String
    let gpuRenderer: String
    let screenWidth: Double
    let screenHeight: Double
    let pixelRatio: Double
    let freeRAMGB: Double
    /// 0...100. 100 when the battery is unsupported, like RN.
    let batteryLevel: Int
    let batteryCharging: Bool
    let batterySupported: Bool
}
