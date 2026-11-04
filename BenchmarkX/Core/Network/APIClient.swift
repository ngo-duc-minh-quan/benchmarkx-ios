import Foundation

final class APIClient {
    struct SaveOutcome {
        let success: Bool
        let id: Int?
        let error: String?
        let savedOffline: Bool
    }

    struct LeaderboardOutcome {
        let success: Bool
        let entries: [LeaderboardEntry]
        let error: String?
    }

    private struct SaveResponse: Decodable {
        let success: Bool
        let id: Int
    }

    private struct LeaderboardResponse: Decodable {
        let results: [LeaderboardEntry]
    }

    private let baseURL: URL
    private let session: URLSession
    private let offlineQueue: OfflineQueue

    init(session: URLSession = .shared, offlineQueue: OfflineQueue = OfflineQueue()) {
        // A real iPhone cannot reach the dev machine's localhost: set API_BASE_URL in Info.plist.
        let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        self.baseURL = configured.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:3000")!
        self.session = session
        self.offlineQueue = offlineQueue
    }

    static func makePayload(_ result: BenchmarkResult, _ hardware: HardwareInfo) -> SaveResultPayload {
        let browser = "BenchmarkX Native v2 (iOS) "
            + "(SC: \(format(result.singleCoreScore)), MC: \(format(result.multiCoreScore)))"

        return SaveResultPayload(
            clientResultId: result.clientResultId,
            deviceName: hardware.deviceName,
            os: hardware.os,
            browser: browser,
            cpuCores: hardware.cpuCores,
            ramGB: hardware.ramGB,
            gpuRenderer: result.gpuRenderer ?? hardware.gpuRenderer,
            avgFPS: result.avgFPS,
            minFPS: result.minFPS,
            onePercentLow: result.onePercentLow,
            cpuScore: result.cpuScore,
            gpuScore: result.gpuScore,
            score: result.score,
            tier: result.tier,
            batteryDrain: result.batteryDrain,
            fpsTimeline: result.fpsTimeline,
            is60HzLocked: result.is60HzLocked,
            effectiveTargetHz: result.effectiveTargetHz,
            singleCoreWorkUnitsPerSec: result.singleCoreWorkUnitsPerSec,
            multiCoreWorkUnitsPerSec: result.multiCoreWorkUnitsPerSec
        )
    }

    func saveResult(_ result: BenchmarkResult, _ hardware: HardwareInfo) async -> SaveOutcome {
        let payload = APIClient.makePayload(result, hardware)
        do {
            let data = try await post(payload)
            let response = try JSONDecoder().decode(SaveResponse.self, from: data)
            return SaveOutcome(success: true, id: response.id, error: nil, savedOffline: false)
        } catch {
            let message = (error as? URLError)?.code == .timedOut
                ? "Server timeout (8s)"
                : "Connection failed"
            await offlineQueue.add(payload)
            return SaveOutcome(success: false, id: nil, error: message, savedOffline: true)
        }
    }

    func fetchLeaderboard() async -> LeaderboardOutcome {
        do {
            let data = try await get(timeout: 8)
            let response = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
            return LeaderboardOutcome(success: true, entries: response.results, error: nil)
        } catch {
            return LeaderboardOutcome(success: false, entries: [], error: error.localizedDescription)
        }
    }

    func syncOfflineQueue() async -> (allSynced: Bool, syncedCount: Int) {
        await offlineQueue.sync { payload in
            _ = try await self.post(payload)
        }
    }

    func pingServer() async -> Bool {
        do {
            _ = try await get(timeout: 3)
            return true
        } catch {
            return false
        }
    }

    private func post(_ payload: SaveResultPayload) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/results"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request)
    }

    private func get(timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/results"))
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    /// Throws on any non-2xx status.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Prints 85.0 as "85" and 60.5 as "60.5", matching the RN client.
    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
