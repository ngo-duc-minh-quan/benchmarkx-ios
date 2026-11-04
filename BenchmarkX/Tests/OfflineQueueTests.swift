import XCTest
@testable import BenchmarkX

final class OfflineQueueTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_queue_\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func makePayload(id: String) -> SaveResultPayload {
        SaveResultPayload(
            clientResultId: id,
            deviceName: "iPhone 11",
            os: "iOS 15",
            browser: "BenchmarkX Native v2 (iOS) (SC: 0, MC: 0)",
            cpuCores: 6,
            ramGB: 4,
            gpuRenderer: "Apple A13 GPU",
            avgFPS: 60,
            minFPS: 55,
            onePercentLow: 58,
            cpuScore: 50,
            gpuScore: 90,
            score: 75,
            tier: .A,
            batteryDrain: 1,
            fpsTimeline: [],
            is60HzLocked: nil,
            effectiveTargetHz: nil,
            singleCoreWorkUnitsPerSec: nil,
            multiCoreWorkUnitsPerSec: nil
        )
    }

    private struct SendFailure: Error {}

    func testAddIgnoresDuplicateClientResultId() async {
        let queue = OfflineQueue(fileURL: fileURL)

        await queue.add(makePayload(id: "a"))
        await queue.add(makePayload(id: "a"))
        await queue.add(makePayload(id: "b"))

        let ids = await queue.load().map(\.clientResultId)
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testSyncKeepsFailedPayloadsAndReportsCount() async {
        let queue = OfflineQueue(fileURL: fileURL)
        await queue.add(makePayload(id: "a"))
        await queue.add(makePayload(id: "b"))
        await queue.add(makePayload(id: "c"))

        let outcome = await queue.sync { payload in
            if payload.clientResultId == "b" { throw SendFailure() }
        }

        XCTAssertFalse(outcome.allSynced)
        XCTAssertEqual(outcome.syncedCount, 2)
        let remaining = await queue.load().map(\.clientResultId)
        XCTAssertEqual(remaining, ["b"])
    }

    func testSyncClearsQueueWhenEverythingSucceeds() async {
        let queue = OfflineQueue(fileURL: fileURL)
        await queue.add(makePayload(id: "a"))

        let outcome = await queue.sync { _ in }

        XCTAssertTrue(outcome.allSynced)
        XCTAssertEqual(outcome.syncedCount, 1)
        let remaining = await queue.load()
        XCTAssertTrue(remaining.isEmpty)
    }
}
