import Foundation

actor OfflineQueue {
    static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_queue.json")
    }

    private let fileURL: URL

    init(fileURL: URL = OfflineQueue.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Returns an empty array when the file is missing or unreadable.
    func load() -> [SaveResultPayload] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SaveResultPayload].self, from: data)) ?? []
    }

    func add(_ payload: SaveResultPayload) {
        var queue = load()
        guard !queue.contains(where: { $0.clientResultId == payload.clientResultId }) else { return }
        queue.append(payload)
        save(queue)
    }

    /// Sends payloads one by one. Failed payloads stay in the queue.
    func sync(
        using send: (SaveResultPayload) async throws -> Void
    ) async -> (allSynced: Bool, syncedCount: Int) {
        let queue = load()
        if queue.isEmpty { return (true, 0) }

        var syncedIds = Set<String>()
        for payload in queue {
            do {
                try await send(payload)
                syncedIds.insert(payload.clientResultId)
            } catch {
                continue
            }
        }

        // Reload: payloads may have been added while awaiting `send`.
        save(load().filter { !syncedIds.contains($0.clientResultId) })
        return (syncedIds.count == queue.count, syncedIds.count)
    }

    private func save(_ queue: [SaveResultPayload]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
