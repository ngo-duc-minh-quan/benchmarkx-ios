import XCTest
import UIKit
@testable import BenchmarkX

final class HardwareDetectorTests: XCTestCase {
    // MARK: - Identifier -> name and chip

    func testIPhone11IsA13() {
        let model = HardwareDetector.deviceModel(for: "iPhone12,1")

        XCTAssertEqual(model.name, "iPhone 11")
        XCTAssertEqual(model.chip, "Apple A13 Bionic")
    }

    func testIPhone16FamilyIsNotSwappedLikeInTheRNTable() {
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,1").name, "iPhone 16 Pro")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,1").chip, "Apple A18 Pro")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,2").name, "iPhone 16 Pro Max")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,3").name, "iPhone 16")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,3").chip, "Apple A18")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone17,4").name, "iPhone 16 Plus")
    }

    func testModelsWithTwoIdentifiersMapToTheSameName() {
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone9,1").name, "iPhone 7")
        XCTAssertEqual(HardwareDetector.deviceModel(for: "iPhone9,3").name, "iPhone 7")
    }

    func testUnknownIdentifierIsReturnedRawWithGenericChip() {
        let model = HardwareDetector.deviceModel(for: "iPhone99,9")

        XCTAssertEqual(model.name, "iPhone99,9")
        XCTAssertEqual(model.chip, "Apple Silicon")
    }

    func testIPadIsNotInTheTableSoItFallsBackToTheRawIdentifier() {
        let model = HardwareDetector.deviceModel(for: "iPad13,4")

        XCTAssertEqual(model.name, "iPad13,4")
        XCTAssertEqual(model.chip, "Apple Silicon")
    }

    // MARK: - Model identifier (device vs Simulator)

    func testRealDeviceUsesHwMachine() {
        XCTAssertEqual(
            HardwareDetector.modelIdentifier(machine: "iPhone12,1", simulatorModelIdentifier: nil),
            "iPhone12,1"
        )
    }

    func testSimulatorUsesTheEnvironmentVariableInsteadOfTheHostArchitecture() {
        XCTAssertEqual(
            HardwareDetector.modelIdentifier(machine: "arm64", simulatorModelIdentifier: "iPhone14,5"),
            "iPhone14,5"
        )
    }

    func testEmptySimulatorVariableFallsBackToHwMachine() {
        XCTAssertEqual(
            HardwareDetector.modelIdentifier(machine: "iPhone12,1", simulatorModelIdentifier: ""),
            "iPhone12,1"
        )
    }

    // MARK: - Bytes to GB, OS string

    func testGigabytesConvertsBytesUsing1024Cubed() {
        XCTAssertEqual(HardwareDetector.gigabytes(fromBytes: 4_294_967_296, decimals: 0), 4)
    }

    func testGigabytesRoundsToTheRequestedDecimals() {
        // 6,000,000,000 bytes = 5.588 GiB
        XCTAssertEqual(HardwareDetector.gigabytes(fromBytes: 6_000_000_000, decimals: 0), 6)
        XCTAssertEqual(HardwareDetector.gigabytes(fromBytes: 6_000_000_000, decimals: 1), 5.6, accuracy: 1e-9)
        XCTAssertEqual(HardwareDetector.gigabytes(fromBytes: 1_610_612_736, decimals: 1), 1.5, accuracy: 1e-9)
    }

    func testGigabytesOfZeroBytesIsZero() {
        XCTAssertEqual(HardwareDetector.gigabytes(fromBytes: 0, decimals: 1), 0)
    }

    func testOSString() {
        XCTAssertEqual(HardwareDetector.osString(systemVersion: "17.4.1"), "iOS 17.4.1")
    }

    // MARK: - Battery

    func testBatteryUnsupportedWhenLevelIsNegative() {
        let battery = HardwareDetector.batteryInfo(level: -1, state: .unknown)

        XCTAssertEqual(battery.level, 100)
        XCTAssertFalse(battery.charging)
        XCTAssertFalse(battery.supported)
    }

    func testBatteryLevelIsRoundedToAPercentage() {
        let battery = HardwareDetector.batteryInfo(level: 0.756, state: .unplugged)

        XCTAssertEqual(battery.level, 76)
        XCTAssertFalse(battery.charging)
        XCTAssertTrue(battery.supported)
    }

    func testChargingAndFullBothCountAsCharging() {
        XCTAssertTrue(HardwareDetector.batteryInfo(level: 0.5, state: .charging).charging)
        XCTAssertTrue(HardwareDetector.batteryInfo(level: 1, state: .full).charging)
    }
}
