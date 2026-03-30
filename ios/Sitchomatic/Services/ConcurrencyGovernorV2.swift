import Foundation

// MARK: - Supporting Types

nonisolated enum GovernorV2Phase: String, Sendable, Codable {
    case rampingUp
    case stable
    case rampingDown
    case emergencyBrake
    case cooldown
}

nonisolated struct RampStrategy: Sendable {
    let initialPairs: Int
    let rampIncrement: Int
    let rampIntervalSeconds: Double
    let cooldownSeconds: Double
}

nonisolated enum GovernorV2Preset: String, Sendable, CaseIterable {
    case conservative
    case balanced
    case m5Overclock

    var strategy: RampStrategy {
        switch self {
        case .conservative:
            return RampStrategy(
                initialPairs: 2,
                rampIncrement: 2,
                rampIntervalSeconds: 45,
                cooldownSeconds: 60
            )
        case .balanced:
            return RampStrategy(
                initialPairs: 5,
                rampIncrement: 5,
                rampIntervalSeconds: 30,
                cooldownSeconds: 45
            )
        case .m5Overclock:
            return RampStrategy(
                initialPairs: 10,
                rampIncrement: 10,
                rampIntervalSeconds: 20,
                cooldownSeconds: 30
            )
        }
    }
}

nonisolated struct TelemetryRecord: Sendable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let pairCount: Int
    let memoryMB: Int
    let successRate: Double
    let completionTimeMs: Double
    let phase: GovernorV2Phase
}

// MARK: - ConcurrencyGovernorV2

@Observable
@MainActor
class ConcurrencyGovernorV2 {
    nonisolated(unsafe) static let shared = ConcurrencyGovernorV2()

    // MARK: - Public State

    private(set) var currentPhase: GovernorV2Phase = .stable
    private(set) var currentPairCount: Int = 0
    private(set) var activePreset: GovernorV2Preset = .balanced
    private(set) var telemetry: [TelemetryRecord] = []
    private(set) var consecutiveStableChecks: Int = 0
    private(set) var isRunning: Bool = false

    var targetPairCount: Int {
        DeviceCapability.performanceProfile.maxConcurrentPairs
    }

    // MARK: - Computed Metrics

    var perPairSuccessRate: Double {
        guard !telemetry.isEmpty else { return 1.0 }
        let recent = telemetry.suffix(20)
        let totalSuccess = recent.reduce(0.0) { $0 + $1.successRate }
        return totalSuccess / Double(recent.count)
    }

    var perPairMemoryDeltaMB: Double {
        guard telemetry.count >= 2 else { return 0.0 }
        let recent = Array(telemetry.suffix(10))
        guard let first = recent.first, let last = recent.last, last.pairCount != first.pairCount else {
            return 0.0
        }
        let memoryDelta = Double(last.memoryMB - first.memoryMB)
        let pairDelta = Double(last.pairCount - first.pairCount)
        return pairDelta != 0 ? memoryDelta / pairDelta : 0.0
    }

    var averageCompletionTimeMs: Double {
        guard !telemetry.isEmpty else { return 0.0 }
        let recent = telemetry.suffix(20)
        let total = recent.reduce(0.0) { $0 + $1.completionTimeMs }
        return total / Double(recent.count)
    }

    var diagnosticSummary: String {
        """
        GovernorV2 [\(activePreset.rawValue)]
        Phase: \(currentPhase.rawValue)
        Pairs: \(currentPairCount)/\(targetPairCount)
        Stable Checks: \(consecutiveStableChecks)/\(stableChecksRequired)
        Success Rate: \(String(format: "%.1f%%", perPairSuccessRate * 100))
        Avg Completion: \(String(format: "%.0fms", averageCompletionTimeMs))
        Memory Delta/Pair: \(String(format: "%.1fMB", perPairMemoryDeltaMB))
        Telemetry Records: \(telemetry.count)
        Running: \(isRunning)
        """
    }

    // MARK: - Private Properties

    private let logger = DebugLogger.shared
    private let profile = DeviceCapability.performanceProfile
    private let stableChecksRequired = 3
    private let maxTelemetryRecords = 100
    private let emergencyFallbackPairs = 10
    private let successRateThreshold = 0.7
    private let completionTimeDegradationFactor = 2.5

    private var evaluationTask: Task<Void, Never>?
    private var lastRampTime: Date = .distantPast
    private var cooldownStartTime: Date?
    private var baselineCompletionTimeMs: Double = 0.0

    // MARK: - Lifecycle

    func start(preset: GovernorV2Preset) {
        guard !isRunning else {
            logger.log("GovernorV2 already running", category: .system, level: .warning)
            return
        }
        activePreset = preset
        let strategy = preset.strategy
        currentPairCount = strategy.initialPairs
        currentPhase = .rampingUp
        consecutiveStableChecks = 0
        cooldownStartTime = nil
        lastRampTime = Date()
        baselineCompletionTimeMs = 0.0
        isRunning = true
        logger.log(
            "GovernorV2 started with \(preset.rawValue) preset",
            category: .system, level: .info,
            detail: "Initial pairs: \(strategy.initialPairs), target: \(targetPairCount)"
        )
        beginPeriodicEvaluation()
    }

    func stop() {
        evaluationTask?.cancel()
        evaluationTask = nil
        isRunning = false
        currentPhase = .stable
        currentPairCount = 0
        consecutiveStableChecks = 0
        logger.log("GovernorV2 stopped", category: .system, level: .info)
    }

    // MARK: - Evaluation

    func evaluate() async {
        guard isRunning else { return }
        let memoryState = MemoryMonitor.shared.update()
        let livePairs = AdaptiveConcurrencyEngine.shared.livePairCount
        let stability = AIPredictiveConcurrencyGovernor.shared.currentStabilityScore
        let strategy = activePreset.strategy
        let successRate = computeSuccessRate(stability: stability)
        let completionTime = estimateCompletionTime()

        switch memoryState.level {
        case .emergency, .critical:
            emergencyBrake()
        case .high:
            handleHighMemory(strategy: strategy)
        case .soft, .normal:
            handleNormalOperation(strategy: strategy, successRate: successRate, completionTime: completionTime)
        }

        recordTelemetry(memoryMB: memoryState.mb, successRate: successRate, completionTimeMs: completionTime)
        logger.log(
            "GovernorV2 evaluated", category: .system, level: .trace,
            detail: "phase=\(currentPhase.rawValue) pairs=\(currentPairCount) mem=\(memoryState.mb)MB live=\(livePairs)"
        )
    }

    // MARK: - Emergency Handling

    func emergencyBrake() {
        let previousPairs = currentPairCount
        currentPairCount = min(emergencyFallbackPairs, currentPairCount)
        currentPhase = .emergencyBrake
        consecutiveStableChecks = 0
        logger.log(
            "GovernorV2 EMERGENCY BRAKE", category: .system, level: .critical,
            detail: "Dropped from \(previousPairs) to \(currentPairCount) pairs"
        )
    }

    func recoverFromEmergency() async {
        guard currentPhase == .emergencyBrake else { return }
        currentPhase = .cooldown
        cooldownStartTime = Date()
        consecutiveStableChecks = 0
        let strategy = activePreset.strategy
        logger.log(
            "GovernorV2 entering cooldown for \(strategy.cooldownSeconds)s",
            category: .system, level: .warning
        )
        try? await Task.sleep(nanoseconds: UInt64(strategy.cooldownSeconds * 1_000_000_000))
        guard isRunning, currentPhase == .cooldown else { return }

        let memoryState = MemoryMonitor.shared.update()
        if memoryState.level == .normal || memoryState.level == .soft {
            currentPhase = .rampingUp
            lastRampTime = Date()
            cooldownStartTime = nil
            logger.log(
                "GovernorV2 recovered, resuming ramp-up", category: .system, level: .info,
                detail: "Memory at \(memoryState.mb)MB, pairs at \(currentPairCount)"
            )
        } else {
            logger.log(
                "GovernorV2 post-cooldown memory still elevated, holding",
                category: .system, level: .warning
            )
            currentPhase = .stable
        }
    }

    // MARK: - Private Evaluation Helpers

    private func handleHighMemory(strategy: RampStrategy) {
        guard currentPhase == .rampingUp || currentPhase == .stable else { return }
        let newCount = max(emergencyFallbackPairs, currentPairCount - strategy.rampIncrement)
        guard newCount < currentPairCount else { return }
        currentPairCount = newCount
        currentPhase = .rampingDown
        consecutiveStableChecks = 0
        logger.log(
            "GovernorV2 ramping down due to high memory", category: .system, level: .warning,
            detail: "Reduced to \(currentPairCount) pairs"
        )
    }

    private func handleNormalOperation(strategy: RampStrategy, successRate: Double, completionTime: Double) {
        if currentPhase == .cooldown { return }
        if currentPhase == .rampingDown {
            currentPhase = .stable
            consecutiveStableChecks = 0
        }

        let timeSinceLastRamp = Date().timeIntervalSince(lastRampTime)
        let isIntervalElapsed = timeSinceLastRamp >= strategy.rampIntervalSeconds

        if successRate >= successRateThreshold && !isPerformanceDegraded(completionTime: completionTime) {
            consecutiveStableChecks += 1
        } else {
            consecutiveStableChecks = max(0, consecutiveStableChecks - 1)
        }

        if consecutiveStableChecks >= stableChecksRequired
            && isIntervalElapsed
            && currentPairCount < targetPairCount {
            currentPairCount = min(targetPairCount, currentPairCount + strategy.rampIncrement)
            currentPhase = .rampingUp
            consecutiveStableChecks = 0
            lastRampTime = Date()
            if baselineCompletionTimeMs == 0.0 && completionTime > 0 {
                baselineCompletionTimeMs = completionTime
            }
            logger.log(
                "GovernorV2 ramped up to \(currentPairCount) pairs", category: .system, level: .info,
                detail: "Target: \(targetPairCount), success: \(String(format: "%.1f%%", successRate * 100))"
            )
        } else if currentPairCount >= targetPairCount {
            currentPhase = .stable
        }
    }

    private func computeSuccessRate(stability: Double) -> Double {
        return max(0.0, min(1.0, stability))
    }

    private func estimateCompletionTime() -> Double {
        guard !telemetry.isEmpty else { return 0.0 }
        let recent = telemetry.suffix(5)
        let total = recent.reduce(0.0) { $0 + $1.completionTimeMs }
        return total / Double(recent.count)
    }

    private func isPerformanceDegraded(completionTime: Double) -> Bool {
        guard baselineCompletionTimeMs > 0, completionTime > 0 else { return false }
        return completionTime > baselineCompletionTimeMs * completionTimeDegradationFactor
    }

    // MARK: - Telemetry

    private func recordTelemetry(memoryMB: Int, successRate: Double, completionTimeMs: Double) {
        let record = TelemetryRecord(
            timestamp: Date(),
            pairCount: currentPairCount,
            memoryMB: memoryMB,
            successRate: successRate,
            completionTimeMs: completionTimeMs,
            phase: currentPhase
        )
        telemetry.append(record)

        if telemetry.count > maxTelemetryRecords {
            telemetry.removeFirst(telemetry.count - maxTelemetryRecords)
        }
    }

    // MARK: - Periodic Evaluation Loop

    private func beginPeriodicEvaluation() {
        evaluationTask?.cancel()

        evaluationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                await self.evaluate()

                let interval = self.currentEvaluationInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private var currentEvaluationInterval: Double {
        let strategy = activePreset.strategy
        switch currentPhase {
        case .emergencyBrake:
            return 5.0
        case .cooldown:
            return 10.0
        case .rampingDown:
            return strategy.rampIntervalSeconds * 0.5
        case .rampingUp:
            return strategy.rampIntervalSeconds
        case .stable:
            return strategy.rampIntervalSeconds * 1.5
        }
    }
}
