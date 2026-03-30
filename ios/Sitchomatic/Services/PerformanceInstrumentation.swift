import Foundation
import os

// MARK: - Subsystem

nonisolated enum InstrumentationSubsystem: String, Sendable, CaseIterable {
    case webView = "webview"
    case batch = "batch"
    case proxy = "proxy"
    case ai = "ai"
    case persistence = "persistence"
    case screenshot = "screenshot"
    case network = "network"
    case ui = "ui"

    var signpostCategory: String {
        switch self {
        case .webView: return "WebView"
        case .batch: return "BatchProcessing"
        case .proxy: return "ProxyLayer"
        case .ai: return "AIEngine"
        case .persistence: return "Persistence"
        case .screenshot: return "Screenshot"
        case .network: return "Network"
        case .ui: return "UserInterface"
        }
    }
}

// MARK: - InstrumentationEvent

nonisolated struct InstrumentationEvent: Sendable, Identifiable {
    let id: UUID
    let subsystem: InstrumentationSubsystem
    let name: String
    let startTime: Date
    var endTime: Date?
    var metadata: [String: String]

    var durationMs: Double? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime) * 1000.0
    }
}

// MARK: - SignpostToken

nonisolated struct SignpostToken: Sendable {
    let id: UUID
    let state: OSSignposter.State
}

// MARK: - PerformanceInstrumentation

@Observable
@MainActor
final class PerformanceInstrumentation {
    nonisolated(unsafe) static let shared = PerformanceInstrumentation()

    // MARK: - Private Properties

    private let logger = DebugLogger.shared

    private static let signpostLog = OSLog(
        subsystem: "com.sitchomatic.performance",
        category: "Signposts"
    )
    private let signposter = OSSignposter(logHandle: signpostLog)

    private let osLogger = os.Logger(
        subsystem: "com.sitchomatic.performance",
        category: "Instrumentation"
    )

    // MARK: - Observable State

    private(set) var activeEvents: [InstrumentationEvent] = []
    private(set) var completedEvents: [InstrumentationEvent] = []
    private(set) var allocationsBySubsystem: [InstrumentationSubsystem: Int64] = [:]

    private let maxCompletedEvents = 200

    // MARK: - Initialization

    private init() {
        for subsystem in InstrumentationSubsystem.allCases {
            allocationsBySubsystem[subsystem] = 0
        }
        logger.log("PerformanceInstrumentation initialized", category: .general)
    }

    // MARK: - Signpost Integration

    func beginSignpost(subsystem: InstrumentationSubsystem, name: String) -> SignpostToken {
        let signpostName = OSSignpostIntervalDescription(stringLiteral: name)
        let state = signposter.beginInterval(signpostName)

        let event = InstrumentationEvent(
            id: UUID(),
            subsystem: subsystem,
            name: name,
            startTime: Date(),
            endTime: nil,
            metadata: [:]
        )
        activeEvents.append(event)

        osLogger.debug("Signpost begin: \(subsystem.rawValue)/\(name)")

        return SignpostToken(id: event.id, state: state)
    }

    func endSignpost(token: SignpostToken) {
        let signpostName: StaticString = "interval"
        signposter.endInterval(signpostName, token.state)

        if let index = activeEvents.firstIndex(where: { $0.id == token.id }) {
            var event = activeEvents.remove(at: index)
            event.endTime = Date()
            appendCompleted(event)

            let durationStr = String(format: "%.2f", event.durationMs ?? 0)
            osLogger.debug("Signpost end: \(event.subsystem.rawValue)/\(event.name) [\(durationStr)ms]")
        }
    }

    // MARK: - Memory Allocation Tracking

    func recordAllocation(subsystem: InstrumentationSubsystem, bytes: Int64, label: String) {
        let current = allocationsBySubsystem[subsystem] ?? 0
        allocationsBySubsystem[subsystem] = current + bytes

        osLogger.debug("Allocation: \(subsystem.rawValue) +\(bytes) bytes (\(label))")
    }

    func resetAllocations() {
        for subsystem in InstrumentationSubsystem.allCases {
            allocationsBySubsystem[subsystem] = 0
        }
        osLogger.info("Allocation counters reset")
    }

    // MARK: - Structured Logging

    func log(
        subsystem: InstrumentationSubsystem,
        message: String,
        level: OSLogType = .default,
        metadata: [String: String] = [:]
    ) {
        let metadataString = metadata.isEmpty
            ? ""
            : " | " + metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")

        osLogger.log(level: level, "[\(subsystem.signpostCategory)] \(message)\(metadataString)")
    }

    // MARK: - Async Measurement

    func measureAsync<T: Sendable>(
        subsystem: InstrumentationSubsystem,
        name: String,
        work: @Sendable () async throws -> T
    ) async rethrows -> T {
        let token = beginSignpost(subsystem: subsystem, name: name)
        do {
            let result = try await work()
            endSignpost(token: token)
            return result
        } catch {
            endSignpost(token: token)
            throw error
        }
    }

    // MARK: - Sync Measurement

    func measure<T>(
        subsystem: InstrumentationSubsystem,
        name: String,
        work: () throws -> T
    ) rethrows -> T {
        let event = InstrumentationEvent(
            id: UUID(),
            subsystem: subsystem,
            name: name,
            startTime: Date(),
            endTime: nil,
            metadata: [:]
        )
        activeEvents.append(event)

        do {
            let result = try work()

            if let index = activeEvents.firstIndex(where: { $0.id == event.id }) {
                var completed = activeEvents.remove(at: index)
                completed.endTime = Date()
                appendCompleted(completed)

                let durationStr = String(format: "%.2f", completed.durationMs ?? 0)
                osLogger.debug("Measured \(subsystem.rawValue)/\(name): \(durationStr)ms")
            }

            return result
        } catch {
            if let index = activeEvents.firstIndex(where: { $0.id == event.id }) {
                var failed = activeEvents.remove(at: index)
                failed.endTime = Date()
                failed.metadata["error"] = String(describing: error)
                appendCompleted(failed)

                osLogger.error("Measured \(subsystem.rawValue)/\(name) failed: \(error.localizedDescription)")
            }
            throw error
        }
    }

    // MARK: - Statistics

    var totalEventCount: Int {
        activeEvents.count + completedEvents.count
    }

    func averageDurationMs(subsystem: InstrumentationSubsystem) -> Double {
        let relevant = completedEvents.filter { $0.subsystem == subsystem }
        guard !relevant.isEmpty else { return 0 }

        let totalMs = relevant.compactMap(\.durationMs).reduce(0, +)
        let count = relevant.compactMap(\.durationMs).count
        guard count > 0 else { return 0 }

        return totalMs / Double(count)
    }

    // MARK: - Diagnostic Summary

    var diagnosticSummary: String {
        var lines: [String] = []
        lines.append("=== Performance Instrumentation Summary ===")
        lines.append("Active events: \(activeEvents.count)")
        lines.append("Completed events: \(completedEvents.count)")
        lines.append("Total tracked: \(totalEventCount)")
        lines.append("")

        lines.append("-- Average Duration by Subsystem --")
        for subsystem in InstrumentationSubsystem.allCases {
            let avg = averageDurationMs(subsystem: subsystem)
            let count = completedEvents.filter { $0.subsystem == subsystem }.count
            if count > 0 {
                lines.append("  \(subsystem.signpostCategory): \(String(format: "%.2f", avg))ms (n=\(count))")
            }
        }
        lines.append("")

        lines.append("-- Memory Allocations by Subsystem --")
        for subsystem in InstrumentationSubsystem.allCases {
            let bytes = allocationsBySubsystem[subsystem] ?? 0
            if bytes > 0 {
                lines.append("  \(subsystem.signpostCategory): \(formattedBytes(bytes))")
            }
        }

        if activeEvents.isEmpty {
            lines.append("")
            lines.append("No active events.")
        } else {
            lines.append("")
            lines.append("-- Active Events --")
            for event in activeEvents.prefix(10) {
                let elapsed = Date().timeIntervalSince(event.startTime) * 1000
                lines.append("  [\(event.subsystem.rawValue)] \(event.name): \(String(format: "%.0f", elapsed))ms elapsed")
            }
            if activeEvents.count > 10 {
                lines.append("  ... and \(activeEvents.count - 10) more")
            }
        }

        lines.append("============================================")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func appendCompleted(_ event: InstrumentationEvent) {
        completedEvents.append(event)
        if completedEvents.count > maxCompletedEvents {
            completedEvents.removeFirst(completedEvents.count - maxCompletedEvents)
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let absBytes = abs(bytes)
        if absBytes < 1024 {
            return "\(bytes) B"
        } else if absBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else if absBytes < 1024 * 1024 * 1024 {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
