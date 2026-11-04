import Foundation
import Metal
import UIKit

/// Reads the hardware of the device the app is running on. Nothing here is tied to one model:
/// every value is read at runtime. Call `detect()` from the main thread (it reads UIScreen and UIDevice).
/// Battery monitoring is enabled inside `detect()`, but the very first read right after enabling can still
/// return -1 (reported as unsupported): enable `UIDevice.isBatteryMonitoringEnabled` earlier if that matters.
enum HardwareDetector {
    private static let unknownChip = "Apple Silicon"

    /// Identifier -> marketing name and chip. Only identifiers checked against external sources are listed:
    /// anything else must stay out, because unknown identifiers fall back to the raw identifier.
    /// Do not copy the RN table: it swaps iPhone17,1/17,2 (16 Pro) with iPhone17,3/17,4 (16).
    private static let modelTable: [(ids: [String], name: String, chip: String)] = [
        (["iPhone8,1"], "iPhone 6s", "Apple A9"),
        (["iPhone8,2"], "iPhone 6s Plus", "Apple A9"),
        (["iPhone8,4"], "iPhone SE (1st generation)", "Apple A9"),
        (["iPhone9,1", "iPhone9,3"], "iPhone 7", "Apple A10 Fusion"),
        (["iPhone9,2", "iPhone9,4"], "iPhone 7 Plus", "Apple A10 Fusion"),
        (["iPhone10,1", "iPhone10,4"], "iPhone 8", "Apple A11 Bionic"),
        (["iPhone10,2", "iPhone10,5"], "iPhone 8 Plus", "Apple A11 Bionic"),
        (["iPhone10,3", "iPhone10,6"], "iPhone X", "Apple A11 Bionic"),
        (["iPhone11,2"], "iPhone XS", "Apple A12 Bionic"),
        (["iPhone11,4", "iPhone11,6"], "iPhone XS Max", "Apple A12 Bionic"),
        (["iPhone11,8"], "iPhone XR", "Apple A12 Bionic"),
        (["iPhone12,1"], "iPhone 11", "Apple A13 Bionic"),
        (["iPhone12,3"], "iPhone 11 Pro", "Apple A13 Bionic"),
        (["iPhone12,5"], "iPhone 11 Pro Max", "Apple A13 Bionic"),
        (["iPhone12,8"], "iPhone SE (2nd generation)", "Apple A13 Bionic"),
        (["iPhone13,1"], "iPhone 12 mini", "Apple A14 Bionic"),
        (["iPhone13,2"], "iPhone 12", "Apple A14 Bionic"),
        (["iPhone13,3"], "iPhone 12 Pro", "Apple A14 Bionic"),
        (["iPhone13,4"], "iPhone 12 Pro Max", "Apple A14 Bionic"),
        (["iPhone14,4"], "iPhone 13 mini", "Apple A15 Bionic"),
        (["iPhone14,5"], "iPhone 13", "Apple A15 Bionic"),
        (["iPhone14,2"], "iPhone 13 Pro", "Apple A15 Bionic"),
        (["iPhone14,3"], "iPhone 13 Pro Max", "Apple A15 Bionic"),
        (["iPhone14,6"], "iPhone SE (3rd generation)", "Apple A15 Bionic"),
        (["iPhone14,7"], "iPhone 14", "Apple A15 Bionic"),
        (["iPhone14,8"], "iPhone 14 Plus", "Apple A15 Bionic"),
        (["iPhone15,2"], "iPhone 14 Pro", "Apple A16 Bionic"),
        (["iPhone15,3"], "iPhone 14 Pro Max", "Apple A16 Bionic"),
        (["iPhone15,4"], "iPhone 15", "Apple A16 Bionic"),
        (["iPhone15,5"], "iPhone 15 Plus", "Apple A16 Bionic"),
        (["iPhone16,1"], "iPhone 15 Pro", "Apple A17 Pro"),
        (["iPhone16,2"], "iPhone 15 Pro Max", "Apple A17 Pro"),
        (["iPhone17,3"], "iPhone 16", "Apple A18"),
        (["iPhone17,4"], "iPhone 16 Plus", "Apple A18"),
        (["iPhone17,5"], "iPhone 16e", "Apple A18"),
        (["iPhone17,1"], "iPhone 16 Pro", "Apple A18 Pro"),
        (["iPhone17,2"], "iPhone 16 Pro Max", "Apple A18 Pro"),
        (["iPhone18,1"], "iPhone 17 Pro", "Apple A19 Pro"),
        (["iPhone18,2"], "iPhone 17 Pro Max", "Apple A19 Pro"),
    ]

    private static let models: [String: (name: String, chip: String)] = Dictionary(
        uniqueKeysWithValues: modelTable.flatMap { row in
            row.ids.map { ($0, (name: row.name, chip: row.chip)) }
        }
    )

    static func detect() -> HardwareInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let identifier = modelIdentifier(
            machine: machineIdentifier(),
            simulatorModelIdentifier: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        )
        let model = deviceModel(for: identifier)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = gigabytes(fromBytes: totalBytes, decimals: 0)
        let freeGB = min(totalGB, gigabytes(fromBytes: freeMemoryBytes() ?? 0, decimals: 1))
        let battery = batteryInfo(level: device.batteryLevel, state: device.batteryState)
        let screen = UIScreen.main

        return HardwareInfo(
            deviceName: model.name,
            os: osString(systemVersion: device.systemVersion),
            cpuCores: ProcessInfo.processInfo.activeProcessorCount,
            ramGB: totalGB,
            socName: model.chip,
            gpuRenderer: MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU",
            screenWidth: Double(screen.bounds.width).rounded(),
            screenHeight: Double(screen.bounds.height).rounded(),
            pixelRatio: Double(screen.scale),
            freeRAMGB: freeGB,
            batteryLevel: battery.level,
            batteryCharging: battery.charging,
            batterySupported: battery.supported
        )
    }

    // MARK: - Pure logic

    /// On the Simulator `hw.machine` is the host architecture ("arm64"), the model is in an environment variable.
    static func modelIdentifier(machine: String, simulatorModelIdentifier: String?) -> String {
        if let simulated = simulatorModelIdentifier, !simulated.isEmpty { return simulated }
        return machine
    }

    /// Unknown identifiers are never guessed: the raw identifier is the name.
    static func deviceModel(for identifier: String) -> (name: String, chip: String) {
        models[identifier] ?? (name: identifier, chip: unknownChip)
    }

    /// Bytes to GiB (1024^3, like RN), rounded to `decimals` places.
    static func gigabytes(fromBytes bytes: UInt64, decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        return (Double(bytes) / 1_073_741_824 * scale).rounded() / scale
    }

    static func osString(systemVersion: String) -> String {
        "iOS \(systemVersion)"
    }

    /// `level` is `UIDevice.batteryLevel`: 0...1, or -1 when unsupported. Charging includes a full battery on charge (like RN).
    static func batteryInfo(level: Float, state: UIDevice.BatteryState) -> (level: Int, charging: Bool, supported: Bool) {
        guard level >= 0 else { return (100, false, false) }
        return (Int((level * 100).rounded()), state == .charging || state == .full, true)
    }

    // MARK: - System reads

    private static func machineIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// System-wide free memory: free + inactive pages. nil if the kernel call fails.
    private static func freeMemoryBytes() -> UInt64? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(pageSize)
    }
}
