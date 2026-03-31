import Foundation

/// Actor-isolated persistence layer providing thread-safe file I/O
/// with atomic writes and coalesced write batching.
///
/// Replaces scattered UserDefaults-based persistence with a single
/// actor that handles all disk I/O off the main actor.
actor PersistenceActor {
    static let shared = PersistenceActor()

    // MARK: - Storage Directory

    private let rootURL: URL
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Write Coalescing

    private var pendingWrites: [String: Data] = [:]
    private var coalescingTask: Task<Void, Never>?
    private let coalescingDelayMilliseconds: UInt64 = 500
    private var writeCount: Int = 0
    private var readCount: Int = 0

    // MARK: - Init

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = docs.appendingPathComponent("PersistenceStore")
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    /// Write a Codable value to a named key. The write is atomic and coalesced.
    func write<T: Encodable & Sendable>(_ value: T, forKey key: String) async throws {
        let data = try encoder.encode(value)
        pendingWrites[key] = data
        scheduleCoalescedFlush()
    }

    /// Read a Codable value from a named key.
    func read<T: Decodable & Sendable>(_ type: T.Type, forKey key: String) async -> T? {
        readCount += 1

        // Check pending writes first (in-flight data takes priority)
        if let pending = pendingWrites[key] {
            return try? decoder.decode(type, from: pending)
        }

        let fileURL = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    /// Write raw data to a named key. Atomic and coalesced.
    func writeData(_ data: Data, forKey key: String) async {
        pendingWrites[key] = data
        scheduleCoalescedFlush()
    }

    /// Read raw data from a named key.
    func readData(forKey key: String) async -> Data? {
        readCount += 1

        if let pending = pendingWrites[key] {
            return pending
        }

        let fileURL = fileURL(forKey: key)
        return try? Data(contentsOf: fileURL)
    }

    /// Remove a persisted key from disk.
    func remove(forKey key: String) async {
        pendingWrites.removeValue(forKey: key)
        let fileURL = fileURL(forKey: key)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Check if a key exists (either in pending writes or on disk).
    func exists(forKey key: String) async -> Bool {
        if pendingWrites[key] != nil { return true }
        return fileManager.fileExists(atPath: fileURL(forKey: key).path)
    }

    /// Force-flush all pending writes immediately (e.g., before app backgrounding or crash).
    func forceSave() async {
        coalescingTask?.cancel()
        coalescingTask = nil
        await flushPendingWrites()
    }

    /// List all stored keys.
    func allKeys() async -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return contents.map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Remove all persisted data.
    func removeAll() async {
        pendingWrites.removeAll()
        let contents = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }

    var diagnosticSummary: String {
        "PersistenceActor: \(pendingWrites.count) pending writes, \(writeCount) total writes, \(readCount) total reads"
    }

    // MARK: - Private

    private func fileURL(forKey key: String) -> URL {
        rootURL.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func ensureDirectoryExists(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Schedule a coalesced flush. Multiple rapid writes within the coalescing window
    /// are batched into a single disk I/O operation.
    private func scheduleCoalescedFlush() {
        coalescingTask?.cancel()
        coalescingTask = Task {
            try? await Task.sleep(for: .milliseconds(coalescingDelayMilliseconds))
            guard !Task.isCancelled else { return }
            await self.flushPendingWrites()
        }
    }

    /// Flush all pending writes to disk atomically.
    private func flushPendingWrites() async {
        guard !pendingWrites.isEmpty else { return }

        let writes = pendingWrites
        pendingWrites.removeAll()

        for (key, data) in writes {
            let fileURL = fileURL(forKey: key)
            do {
                try data.write(to: fileURL, options: .atomic)
                writeCount += 1
            } catch {
                // Re-queue failed writes for next flush
                pendingWrites[key] = data
            }
        }
    }
}
