import Foundation
import os.signpost

// MARK: - Performance Instrumentation (Swift 6.2)

@MainActor
final class PerformanceInstrumentation {
    nonisolated(unsafe) static let shared = PerformanceInstrumentation()

    private let logger = DebugLogger.shared

    // Signpost logging
    private let signpostLog = OSLog(subsystem: "com.sitchomatic.app", category: "Performance")

    // Subsystem memory tracking
    private var subsystemMemory: [String: Double] = [:]

    private init() {
        logger.log("PerformanceInstrumentation: initialized with os_signpost support", category: .performance, level: .info)
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
            defer {
                await self.logTaskCompletion(name: name)
            }

            await self.logTaskStart(name: name)
            return try await operation()
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
        logger.log("PerformanceInstrumentation: cleaning up WebView \(id.prefix(8))", category: .performance, level: .debug)

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

        logger.log("PerformanceInstrumentation: \(subsystem) allocated \(Int(sizeMB))MB (total: \(Int(subsystemMemory[subsystem] ?? 0))MB)", category: .performance, level: .debug)
    }

    func trackMemoryDeallocation(subsystem: String, sizeMB: Double) {
        subsystemMemory[subsystem, default: 0] -= sizeMB

        logger.log("PerformanceInstrumentation: \(subsystem) deallocated \(Int(sizeMB))MB (total: \(Int(subsystemMemory[subsystem] ?? 0))MB)", category: .performance, level: .debug)
    }

    func getMemoryBySubsystem() -> [String: Double] {
        subsystemMemory
    }

    func resetMemoryTracking() {
        subsystemMemory.removeAll()
        logger.log("PerformanceInstrumentation: memory tracking reset", category: .performance, level: .info)
    }

    // MARK: - Private Helpers

    private func logTaskStart(name: String) {
        logger.log("PerformanceInstrumentation: task '\(name)' started", category: .performance, level: .debug)
        signpostEvent("Task Start", name)
    }

    private func logTaskCompletion(name: String) {
        logger.log("PerformanceInstrumentation: task '\(name)' completed", category: .performance, level: .debug)
        signpostEvent("Task Complete", name)
    }
}

// MARK: - Build Optimization Guide

/*
 # Build Optimization: One-Type-Per-File

 For faster incremental builds, follow these guidelines:

 ✅ Good (One type per file):
 - LoginCredential.swift (struct LoginCredential)
 - PPSRCard.swift (struct PPSRCard)
 - NetworkFailure.swift (enum NetworkFailure)

 ❌ Avoid (Multiple types in one file):
 - Models.swift (LoginCredential + PPSRCard + UnifiedSession)

 ## Benefits:
 - Faster incremental compilation
 - Better module isolation
 - Clearer code organization
 - Easier to find definitions

 ## Current Status:
 Most files in ios/Sitchomatic/Services/ follow this pattern.
 Models in ios/Sitchomatic/Models/ are already split.

 ## Action Items:
 - Review Services/ for any files with multiple unrelated types
 - Consider splitting large service files (>1000 lines)
 - Ensure test files mirror source structure
 */

// MARK: - Usage Examples

extension PerformanceInstrumentation {
    /*
     // Example 1: Named Task
     let task = PerformanceInstrumentation.shared.namedTask("Process Batch") {
         await processBatch()
     }

     // Example 2: WebView with Automatic Cleanup
     try await PerformanceInstrumentation.shared.withWebViewCleanup(webViewId: id) {
         try await webView.loadPage(url)
     }

     // Example 3: Signpost Measurement
     await PerformanceInstrumentation.shared.measureBatchExecution {
         await runAutomation()
     }

     // Example 4: Memory Tracking
     PerformanceInstrumentation.shared.trackMemoryAllocation(subsystem: "WebViews", sizeMB: 45.2)

     // Example 5: Manual Signposts for Fine-Grained Control
     let signpostID = OSSignpostID(log: PerformanceInstrumentation.shared.signpostLog)
     PerformanceInstrumentation.shared.beginSignpost("Custom Operation", id: signpostID)
     // ... perform operation ...
     PerformanceInstrumentation.shared.endSignpost("Custom Operation", id: signpostID)
     */
}
