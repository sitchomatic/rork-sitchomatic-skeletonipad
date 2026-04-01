import Foundation
import Observation
import ActivityKit

/// Bridges batch state from BatchStateManager to the Widget/Live Activity layer.
/// Writes to shared App Group UserDefaults so the widget timeline provider can read.
@Observable
@MainActor
final class WidgetBridgeService {
    static let shared = WidgetBridgeService()

    // MARK: - State

    private(set) var isLiveActivityActive: Bool = false
    private var updateTask: Task<Void, Never>?
    private var activeActivity: Activity<CommandCenterActivityAttributes>?

    private let logger = DebugLogger.shared
    private let suiteName = "group.com.sitchomatic.shared"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private init() {}

    // MARK: - Widget Data

    func updateWidgetData() {
        let batch = BatchStateManager.shared
        let engine = AdaptiveConcurrencyEngine.shared

        let defaults = sharedDefaults ?? UserDefaults.standard
        defaults.set(batch.isRunning, forKey: "widget_isRunning")
        defaults.set(batch.isPaused, forKey: "widget_isPaused")
        defaults.set(batch.successCount, forKey: "widget_successCount")
        defaults.set(batch.failureCount, forKey: "widget_failureCount")
        defaults.set(batch.totalCount, forKey: "widget_totalCount")
        defaults.set(batch.elapsedSeconds, forKey: "widget_elapsedSeconds")
        defaults.set(engine.livePairCount, forKey: "widget_pairCount")
        defaults.set(batch.throughputPerMinute, forKey: "widget_throughputPerMinute")

        let eta = estimateETA(batch: batch)
        defaults.set(eta, forKey: "widget_eta")
        defaults.synchronize()
    }

    // MARK: - Live Activity

    func startLiveActivity(siteLabel: String = "Sitchomatic", siteMode: String = "joe", batchLabel: String = "Batch Run") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.log("Live Activities not enabled", category: .system, level: .warning)
            return
        }

        let batch = BatchStateManager.shared
        let engine = AdaptiveConcurrencyEngine.shared
        let attributes = CommandCenterActivityAttributes(siteLabel: siteLabel, siteMode: siteMode, batchLabel: batchLabel)
        let completed = batch.successCount + batch.failureCount
        let successRate = completed > 0 ? Double(batch.successCount) / Double(completed) : 0
        let state = CommandCenterActivityAttributes.ContentState(
            completedCount: completed,
            totalCount: batch.totalCount,
            workingCount: batch.successCount,
            failedCount: batch.failureCount,
            statusLabel: batch.isPaused ? "PAUSED" : "RUNNING",
            elapsedSeconds: Int(batch.elapsedSeconds),
            isPaused: batch.isPaused,
            isStopping: batch.isStopping,
            successRate: successRate,
            throughputPerMinute: batch.throughputPerMinute,
            eta: estimateETA(batch: batch),
            pairCount: engine.livePairCount
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            activeActivity = activity
            isLiveActivityActive = true
            logger.log("Live Activity started", category: .system, level: .success)
        } catch {
            logger.log("Failed to start Live Activity: \(error.localizedDescription)", category: .system, level: .error)
        }
    }

    func updateLiveActivity() {
        guard let activity = activeActivity else { return }

        let batch = BatchStateManager.shared
        let engine = AdaptiveConcurrencyEngine.shared
        let completed = batch.successCount + batch.failureCount
        let successRate = completed > 0 ? Double(batch.successCount) / Double(completed) : 0
        let statusLabel: String = batch.isStopping ? "STOPPING" : (batch.isPaused ? "PAUSED" : "RUNNING")
        let state = CommandCenterActivityAttributes.ContentState(
            completedCount: completed,
            totalCount: batch.totalCount,
            workingCount: batch.successCount,
            failedCount: batch.failureCount,
            statusLabel: statusLabel,
            elapsedSeconds: Int(batch.elapsedSeconds),
            isPaused: batch.isPaused,
            isStopping: batch.isStopping,
            successRate: successRate,
            throughputPerMinute: batch.throughputPerMinute,
            eta: estimateETA(batch: batch),
            pairCount: engine.livePairCount
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endLiveActivity() {
        guard let activity = activeActivity else { return }

        let batch = BatchStateManager.shared
        let completed = batch.successCount + batch.failureCount
        let successRate = completed > 0 ? Double(batch.successCount) / Double(completed) : 0
        let finalState = CommandCenterActivityAttributes.ContentState(
            completedCount: completed,
            totalCount: batch.totalCount,
            workingCount: batch.successCount,
            failedCount: batch.failureCount,
            statusLabel: "COMPLETE",
            elapsedSeconds: Int(batch.elapsedSeconds),
            isPaused: false,
            isStopping: false,
            successRate: successRate,
            throughputPerMinute: batch.throughputPerMinute,
            eta: "—",
            pairCount: 0
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 300))
            await MainActor.run {
                self.activeActivity = nil
                self.isLiveActivityActive = false
            }
            logger.log("Live Activity ended", category: .system, level: .info)
        }
    }

    // MARK: - Periodic Updates

    func startPeriodicUpdates(intervalSeconds: TimeInterval = 5) {
        stopPeriodicUpdates()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateWidgetData()
                if self?.isLiveActivityActive == true {
                    self?.updateLiveActivity()
                }
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    func stopPeriodicUpdates() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - Helpers

    private func estimateETA(batch: BatchStateManager) -> String {
        let completed = batch.successCount + batch.failureCount
        guard completed > 0, batch.totalCount > completed else { return "—" }
        let remaining = batch.totalCount - completed
        let rate = batch.throughputPerMinute
        guard rate > 0 else { return "—" }
        let minutesLeft = Double(remaining) / rate
        if minutesLeft < 1 { return "<1m" }
        if minutesLeft < 60 { return "\(Int(minutesLeft))m" }
        return "\(Int(minutesLeft / 60))h \(Int(minutesLeft.truncatingRemainder(dividingBy: 60)))m"
    }
}
