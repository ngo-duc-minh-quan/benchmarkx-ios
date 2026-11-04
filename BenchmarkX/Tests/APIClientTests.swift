import XCTest
@testable import BenchmarkX

final class APIClientTests: XCTestCase {
    private func makeResult(gpuRenderer: String?) -> BenchmarkResult {
        var result = ScoreCalculator.calculate(
            fpsArray: [60, 60, 60],
            frameTimesMs: [],
            batteryDrain: 1,
            singleCoreScore: 85,
            multiCoreScore: 60.5,
            targetHz: 60,
            clientResultId: "test-id"
        )
        result.gpuRenderer = gpuRenderer
        return result
    }

    private let hardware = HardwareInfo(
        deviceName: "iPhone 11",
        os: "iOS 15.0",
        cpuCores: 6,
        ramGB: 4,
        socName: "A13 Bionic",
        gpuRenderer: "Apple A13 GPU (hardware)",
        screenWidth: 414,
        screenHeight: 896,
        pixelRatio: 2
    )

    func testMakePayloadBuildsBrowserString() {
        let payload = APIClient.makePayload(makeResult(gpuRenderer: nil), hardware)

        XCTAssertEqual(payload.browser, "BenchmarkX Native v2 (iOS) (SC: 85, MC: 60.5)")
        XCTAssertEqual(payload.clientResultId, "test-id")
        XCTAssertEqual(payload.deviceName, "iPhone 11")
    }

    func testMakePayloadPrefersResultGpuRendererAndFallsBackToHardware() {
        let fromResult = APIClient.makePayload(makeResult(gpuRenderer: "Metal X"), hardware)
        XCTAssertEqual(fromResult.gpuRenderer, "Metal X")

        let fromHardware = APIClient.makePayload(makeResult(gpuRenderer: nil), hardware)
        XCTAssertEqual(fromHardware.gpuRenderer, "Apple A13 GPU (hardware)")
    }
}
