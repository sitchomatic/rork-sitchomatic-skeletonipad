import Foundation
import os.signpost

// MARK: - Performance Instrumentation (Swift 6.2)

@MainActor
final class PerformanceInstrumentation {
    static let shared = PerformanceInstrumentation()

    private let logger = DebugLogger.shared

    // Signpost logging
    private let signpostLog = OSLog(subsystem: "com.sitchomatic.app", category: "Performance")

    // Subsystem memory tracking
    private var subsystemMemory: [String: Double] = [:]

    private init() {
        logger.log("PerformanceInstrumentation: initialized with os_signpost support", category: .system, level: .info)
    }

    // MARK: - Task Naming (Swift 6.2)

    func namedTask<T>(
        _ name: String,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        Task(priority: priority) {
            defer {
                logTaskCompletion(name: name)
            }

            logTaskStart(name: name)
            return try await operation()
        }
    }

    func namedDetachedTask<T>(
        _ name: String,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        Task.detached(priority: priority) {
            await self.logTaskStart(name: name)
            let result = try await operation()
            await self.logTaskCompletion(name: name)
            return result
        }
    }

    // MARK: - Async Defer for WebView Cleanup

    func withWebViewCleanup<T>(
        webViewId: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        defer {
            Task {
                await cleanupWebView(id: webViewId)
            }
        }

        return try await operation()
    }

    private func cleanupWebView(id: String) async {
        logger.log("PerformanceInstrumentation: cleaning up WebView \(id.prefix(8))", category: .system, level: .debug)

        // Cleanup operations
        // - Release WKWebView
        // - Clear cached data
        // - Remove from recycler pool
    }

    // MARK: - Structured Logging with os_signpost

    func beginSignpost(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
    }

    func endSignpost(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: signpostLog, name: name, signpostID: id)
    }

    func signpostEvent(_ name: StaticString, _ message: String = "") {
        os_signpost(.event, log: signpostLog, name: name, "%{public}s", message)
    }

    // Convenience methods for common operations

    func measureBatchExecution<T>(_ operation: () async throws -> T) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "Batch Execution", signpostID: signpostID)

        defer {
            os_signpost(.end, log: signpostLog, name: "Batch Execution", signpostID: signpostID)
        }

        return try await operation()
    }

    func measureWebViewLoad<T>(_ operation: () async throws -> T) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "WebView Load", signpostID: signpostID)

        defer {
            os_signpost(.end, log: signpostLog, name: "WebView Load", signpostID: signpostID)
        }

        return try await operation()
    }

    func measureAIRequest<T>(_ operation: () async throws -> T) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "AI Request", signpostID: signpostID)

        defer {
            os_signpost(.end, log: signpostLog, name: "AI Request", signpostID: signpostID)
        }

        return try await operation()
    }

    // MARK: - Memory Allocation Tracking

    func trackMemoryAllocation(subsystem: String, sizeMB: Double) {
        subsystemMemory[subsystem, default: 0] += sizeMB

        logger.log("PerformanceInstrumentation: \(subsystem) allocated \(Int(sizeMB))MB (total: \(Int(subsystemMemory[subsystem] ?? 0))MB)", category: .system, level: .debug)
    }

    func trackMemoryDeallocation(subsystem: String, sizeMB: Double) {
        subsystemMemory[subsystem, default: 0] -= sizeMB

        logger.log("PerformanceInstrumentation: \(subsystem) deallocated \(Int(sizeMB))MB (total: \(Int(subsystemMemory[subsystem] ?? 0))MB)", category: .system, level: .debug)
    }

    func getMemoryBySubsystem() -> [String: Double] {
        subsystemMemory
    }

    func resetMemoryTracking() {
        subsystemMemory.removeAll()
        logger.log("PerformanceInstrumentation: memory tracking reset", category: .system, level: .info)
    }

    // MARK: - Private Helpers

    private func logTaskStart(name: String) {
        logger.log("PerformanceInstrumentation: task '\(name)' started", category: .system, level: .debug)
        signpostEvent("Task Start", name)
    }

    private func logTaskCompletion(name: String) {
        logger.log("PerformanceInstrumentation: task '\(name)' completed", category: .system, level: .debug)
        signpostEvent("Task Complete", name)
    }
}
