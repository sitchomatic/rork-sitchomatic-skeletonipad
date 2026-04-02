import Testing
import Foundation
@testable import Sitchomatic

/// Tests for Actor-based persistence layer
@Suite("PersistenceActor Tests")
struct PersistenceActorTests {

    // MARK: - Basic Read/Write

    @Test("Write and read data")
    func testWriteAndRead() async throws {
        let actor = PersistenceActor.shared

        let testData = ["key": "value", "number": "123"]
        try await actor.write(testData, forKey: "test-key")

        let retrieved = await actor.read([String: String].self, forKey: "test-key")
        #expect(retrieved?["key"] == "value")
        #expect(retrieved?["number"] == "123")

        // Cleanup
        await actor.remove(forKey: "test-key")
    }

    @Test("Read non-existent key returns nil")
    func testReadNonExistent() async {
        let actor = PersistenceActor.shared
        let result = await actor.read([String: String].self, forKey: "non-existent-\(UUID().uuidString)")
        #expect(result == nil)
    }

    // MARK: - Concurrent Access

    @Test("Concurrent writes don't corrupt data")
    func testConcurrentWrites() async throws {
        let actor = PersistenceActor.shared
        let prefix = "concurrent-test-\(UUID().uuidString)"

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    try? await actor.write(["value": "\(i)"], forKey: "\(prefix)-\(i)")
                }
            }
        }

        // Verify all writes succeeded
        for i in 0..<100 {
            let result = await actor.read([String: String].self, forKey: "\(prefix)-\(i)")
            #expect(result?["value"] == "\(i)")
        }

        // Cleanup
        for i in 0..<100 {
            await actor.remove(forKey: "\(prefix)-\(i)")
        }
    }

    @Test("Concurrent reads of same key")
    func testConcurrentReads() async throws {
        let actor = PersistenceActor.shared
        let key = "concurrent-read-test-\(UUID().uuidString)"

        let testData = ["key": "value"]
        try await actor.write(testData, forKey: key)

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    if let result = await actor.read([String: String].self, forKey: key) {
                        return result["key"] == "value"
                    }
                    return false
                }
            }

            var successCount = 0
            for await success in group {
                if success {
                    successCount += 1
                }
            }
            #expect(successCount == 100)
        }

        // Cleanup
        await actor.remove(forKey: key)
    }

    // MARK: - Coalesced Writes

    @Test("Rapid writes are coalesced")
    func testWriteCoalescing() async throws {
        let actor = PersistenceActor.shared
        let key = "coalesce-test-\(UUID().uuidString)"

        // Perform many rapid writes
        for i in 0..<50 {
            try await actor.write(["counter": "\(i)"], forKey: key)
        }

        // Wait for coalescing window
        try await Task.sleep(for: .milliseconds(600))

        // Force save to ensure pending writes are flushed
        await actor.forceSave()

        // Verify final value
        let result = await actor.read([String: String].self, forKey: key)
        #expect(result?["counter"] == "49")

        // Cleanup
        await actor.remove(forKey: key)
    }

    // MARK: - Force Save

    @Test("Force save flushes pending writes")
    func testForceSave() async throws {
        let actor = PersistenceActor.shared
        let key = "force-save-test-\(UUID().uuidString)"

        try await actor.write(["status": "pending"], forKey: key)
        await actor.forceSave()

        let result = await actor.read([String: String].self, forKey: key)
        #expect(result?["status"] == "pending")

        // Cleanup
        await actor.remove(forKey: key)
    }

    // MARK: - Error Handling

    @Test("Invalid JSON encoding fails gracefully")
    func testInvalidEncoding() async {
        let actor = PersistenceActor.shared
        let key = "invalid-\(UUID().uuidString)"

        struct InvalidPayload: Codable {
            let value: Double
        }

        do {
            try await actor.write(InvalidPayload(value: .nan), forKey: key)
            // Cleanup in case write unexpectedly succeeds
            await actor.remove(forKey: key)
            Issue.record("Expected write to throw an EncodingError for non-conforming floating-point value")
        } catch {
            #expect(error is EncodingError)
        }
    }

    // MARK: - Memory Safety

    @Test("Large data doesn't cause memory issues")
    func testLargeData() async throws {
        let actor = PersistenceActor.shared
        let key = "large-data-test-\(UUID().uuidString)"

        let largeArray = Array(repeating: "test string", count: 10000)
        try await actor.write(largeArray, forKey: key)

        let result = await actor.read([String].self, forKey: key)
        #expect(result?.count == 10000)

        // Cleanup
        await actor.remove(forKey: key)
    }

    // MARK: - Cleanup

    @Test("Remove data works correctly")
    func testRemoveData() async throws {
        let actor = PersistenceActor.shared
        let key = "remove-test-\(UUID().uuidString)"

        try await actor.write(["key": "value"], forKey: key)

        // Verify it exists
        let before = await actor.read([String: String].self, forKey: key)
        #expect(before != nil)

        // Remove it
        await actor.remove(forKey: key)

        // Verify it's gone
        let after = await actor.read([String: String].self, forKey: key)
        #expect(after == nil)
    }
}
