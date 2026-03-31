import Foundation
import Observation

/// Centralized batch execution state manager.
/// Replaces duplicated pause/resume/stop/heartbeat/timing logic across
/// LoginViewModel, PPSRAutomationViewModel, and UnifiedSessionViewModel.
@Observable
@MainActor
final class BatchStateManager {
    static let shared = BatchStateManager()

    // MARK: - Batch State

    private(set) var isRunning: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var isStopping: Bool = false
    private(set) var pauseCountdown: Int = 0

    private(set) var batchStartTime: Date?
    private(set) var batchEndTime: Date?
    private(set) var successCount: Int = 0
    private(set) var failureCount: Int = 0
    private(set) var totalCount: Int = 0

    var elapsedSeconds: TimeInterval {
        guard let start = batchStartTime else { return 0 }
        let end = batchEndTime ?? Date()
        return end.timeIntervalSince(start)
    }

    var throughputPerMinute: Double {
        let elapsed = elapsedSeconds
        guard elapsed > 0 else { return 0 }
        return Double(successCount + failureCount) / (elapsed / 60.0)
    }

    // MARK: - Callbacks

    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onForceStop: (() -> Void)?
    var onEmergencyStop: (() -> Void)?

    // MARK: - Private

    private var pauseCountdownTask: Task<Void, Never>?
    private var forceStopTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private let logger = DebugLogger.shared

    private var forceStopDelaySeconds: TimeInterval {
        DeviceCapability.isM5Class ? 45 : (DeviceCapability.isHighPerformanceDevice ? 30 : 20)
    }
    private let pauseDurationSeconds: Int = 60
    private var heartbeatIntervalSeconds: TimeInterval {
        DeviceCapability.isM5Class ? 10 : 15
    }

    private init() {}

    // MARK: - Batch Lifecycle

    func startBatch(totalItems: Int = 0) {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        isStopping = false
        pauseCountdown = 0
        successCount = 0
        failureCount = 0
        totalCount = totalItems
        batchStartTime = Date()
        batchEndTime = nil

        // Pre-warm recycler pool at batch start
        WebViewRecycler.shared.prewarm()

        startHeartbeat()
        logger.log("BatchStateManager: batch started (total=\(totalItems))", category: .automation, level: .info)
    }

    func finalizeBatch() {
        isRunning = false
        isPaused = false
        isStopping = false
        pauseCountdown = 0
        batchEndTime = Date()

        cancelPauseCountdown()
        cancelForceStop()
        cancelHeartbeat()

        let elapsed = elapsedSeconds
        logger.log("BatchStateManager: batch finalized (success=\(successCount), failed=\(failureCount), elapsed=\(Int(elapsed))s)", category: .automation, level: .info)
    }

    // MARK: - Pause / Resume / Stop

    func pause() {
        guard isRunning, !isPaused, !isStopping else { return }
        isPaused = true
        pauseCountdown = pauseDurationSeconds
        startPauseCountdown()
        onPause?()
        logger.log("BatchStateManager: paused for \(pauseDurationSeconds)s", category: .automation, level: .warning)
    }

    func resume() {
        guard isPaused else { return }
        cancelPauseCountdown()
        isPaused = false
        pauseCountdown = 0
        onResume?()
        logger.log("BatchStateManager: resumed", category: .automation, level: .info)
    }

    func stop() {
        guard isRunning, !isStopping else { return }
        isStopping = true
        isPaused = false
        pauseCountdown = 0
        cancelPauseCountdown()
        startForceStopTimer()
        logger.log("BatchStateManager: stopping — waiting for active sessions to finish", category: .automation, level: .warning)
    }

    func emergencyStop() {
        logger.log("BatchStateManager: EMERGENCY STOP", category: .system, level: .critical)

        // Flush recycler pool
        WebViewRecycler.shared.emergencyFlush()

        // Reset tracking
        DeadSessionDetector.shared.stopAllWatchdogs()
        SessionActivityMonitor.shared.stopAll()
        WebViewTracker.shared.reset()

        onEmergencyStop?()
        finalizeBatch()
    }

    // MARK: - Counters

    func recordSuccess() {
        successCount += 1
    }

    func recordFailure() {
        failureCount += 1
    }

    func updateTotalCount(_ total: Int) {
        totalCount = total
    }

    // MARK: - Pause Countdown

    private func startPauseCountdown() {
        cancelPauseCountdown()
        pauseCountdownTask = Task { [weak self] in
            while let self, self.pauseCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.pauseCountdown -= 1
            }
            guard !Task.isCancelled, let self else { return }
            if self.isPaused {
                self.resume()
            }
        }
    }

    private func cancelPauseCountdown() {
        pauseCountdownTask?.cancel()
        pauseCountdownTask = nil
    }

    // MARK: - Force Stop Timer

    private func startForceStopTimer() {
        cancelForceStop()
        forceStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.forceStopDelaySeconds ?? 30))
            guard !Task.isCancelled, let self else { return }
            if self.isStopping {
                self.logger.log("BatchStateManager: force stop timer expired — forcing finalize", category: .automation, level: .critical)
                self.onForceStop?()
                self.finalizeBatch()
            }
        }
    }

    private func cancelForceStop() {
        forceStopTask?.cancel()
        forceStopTask = nil
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        cancelHeartbeat()
        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(for: .seconds(self.heartbeatIntervalSeconds))
                guard !Task.isCancelled, self.isRunning else { break }

                let memMB = CrashProtectionService.shared.currentMemoryUsageMB()
                let elapsed = Int(self.elapsedSeconds)
                self.logger.log("BatchStateManager: heartbeat — \(self.successCount)/\(self.totalCount) done, \(self.failureCount) failed, \(elapsed)s elapsed, \(memMB)MB memory", category: .automation, level: .trace)
            }
        }
    }

    private func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Diagnostics

    var diagnosticSummary: String {
        let state: String
        if !isRunning { state = "idle" }
        else if isPaused { state = "paused(\(pauseCountdown)s)" }
        else if isStopping { state = "stopping" }
        else { state = "running" }

        return "Batch: \(state) | \(successCount)/\(totalCount) (\(failureCount) failed) | \(String(format: "%.1f", throughputPerMinute))/min | \(Int(elapsedSeconds))s"
    }

    func reset() {
        if isRunning { finalizeBatch() }
        successCount = 0
        failureCount = 0
        totalCount = 0
        batchStartTime = nil
        batchEndTime = nil
        onPause = nil
        onResume = nil
        onForceStop = nil
        onEmergencyStop = nil
    }
}
