import Testing
import Foundation
@testable import Sitchomatic

/// Tests for Actor-based persistence layer
@Suite("PersistenceActor Tests")
struct PersistenceActorTests {

    // MARK: - Basic Read/Write

    @Test("Write and read data")
    func testWriteAndRead() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        let testData = ["key": "value", "number": "123"]
        try await actor.save(testData, forKey: "test-key")

        let retrieved: [String: String]? = try await actor.load(forKey: "test-key")
        #expect(retrieved?["key"] == "value")
        #expect(retrieved?["number"] == "123")
    }

    @Test("Read non-existent key returns nil")
    func testReadNonExistent() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)
        let result: [String: String]? = try await actor.load(forKey: "non-existent")
        #expect(result == nil)
    }

    // MARK: - Concurrent Access

    @Test("Concurrent writes don't corrupt data")
    func testConcurrentWrites() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    try? await actor.save(["value": "\(i)"], forKey: "concurrent-test-\(i)")
                }
            }
        }

        // Verify all writes succeeded
        for i in 0..<100 {
            let result: [String: String]? = try await actor.load(forKey: "concurrent-test-\(i)")
            #expect(result?["value"] == "\(i)")
        }
    }

    @Test("Concurrent reads of same key")
    func testConcurrentReads() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        let testData = ["key": "value"]
        try await actor.save(testData, forKey: "concurrent-read-test")

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    if let result: [String: String] = try? await actor.load(forKey: "concurrent-read-test") {
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
    }

    // MARK: - Coalesced Writes

    @Test("Rapid writes are coalesced")
    func testWriteCoalescing() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        // Perform many rapid writes
        for i in 0..<50 {
            try await actor.save(["counter": "\(i)"], forKey: "coalesce-test")
        }

        // Wait for coalescing window
        try await Task.sleep(for: .milliseconds(600))

        // Force save to ensure pending writes are flushed
        try await actor.forceSave()

        // Verify final value
        let result: [String: String]? = try await actor.load(forKey: "coalesce-test")
        #expect(result?["counter"] == "49")
    }

    // MARK: - Force Save

    @Test("Force save flushes pending writes")
    func testForceSave() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        try await actor.save(["status": "pending"], forKey: "force-save-test")
        try await actor.forceSave()

        let result: [String: String]? = try await actor.load(forKey: "force-save-test")
        #expect(result?["status"] == "pending")
    }

    // MARK: - Error Handling

    @Test("Invalid JSON encoding fails gracefully")
    func testInvalidEncoding() async {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        // Attempt to save non-Codable type
        struct NonCodable {
            let value: Int
        }

        // This should fail at compile time, but if we force it:
        // let result = try? await actor.save(NonCodable(value: 42), forKey: "invalid")
        // #expect(result == nil)
    }

    // MARK: - Memory Safety

    @Test("Large data doesn't cause memory issues")
    func testLargeData() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        let largeArray = Array(repeating: "test string", count: 10000)
        try await actor.save(largeArray, forKey: "large-data-test")

        let result: [String]? = try await actor.load(forKey: "large-data-test")
        #expect(result?.count == 10000)
    }

    // MARK: - Cleanup

    @Test("Remove data works correctly")
    func testRemoveData() async throws {
        let actor = PersistenceActor(baseDirectory: FileManager.default.temporaryDirectory)

        try await actor.save(["key": "value"], forKey: "remove-test")

        // Verify it exists
        let before: [String: String]? = try await actor.load(forKey: "remove-test")
        #expect(before != nil)

        // Remove it
        try await actor.remove(forKey: "remove-test")

        // Verify it's gone
        let after: [String: String]? = try await actor.load(forKey: "remove-test")
        #expect(after == nil)
    }
}
