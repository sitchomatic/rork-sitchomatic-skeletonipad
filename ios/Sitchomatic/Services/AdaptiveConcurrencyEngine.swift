import Foundation
import UIKit
import Observation

nonisolated enum ConcurrencyFactorLevel: String, Codable, Sendable {
    case good = "good"
    case warning = "warning"
    case critical = "critical"

    var color: String {
        switch self {
        case .good: "green"
        case .warning: "yellow"
        case .critical: "red"
        }
    }
}

nonisolated struct ConcurrencyFactorScores: Sendable {
    let memory: ConcurrencyFactorLevel
    let memoryMB: Int
    let network: ConcurrencyFactorLevel
    let networkLatencyMs: Int
    let successRate: Double
    let successLevel: ConcurrencyFactorLevel
    let stability: Double
    let stabilityLevel: ConcurrencyFactorLevel
    let isBackground: Bool
}

nonisolated struct ConcurrencyDecision: Codable, Sendable, Identifiable {
    let id: String
    let timestamp: Date
    let fromConcurrency: Int
    let toConcurrency: Int
    let reasoning: String
    let wasAI: Bool
    let memoryMB: Int
    let successRate: Double
    let stability: Double
    let isBackground: Bool

    var direction: ConcurrencyDirection {
        if toConcurrency > fromConcurrency { return .rampUp }
        if toConcurrency < fromConcurrency { return .rampDown }
        return .hold
    }

    nonisolated enum ConcurrencyDirection: String, Codable, Sendable {
        case rampUp
        case rampDown
        case hold
    }
}

nonisolated struct ConcurrencyHistoryPoint: Sendable {
    let timestamp: Date
    let concurrency: Int
}

@Observable
@MainActor
class AdaptiveConcurrencyEngine {
    static let shared = AdaptiveConcurrencyEngine()

    private(set) var livePairCount: Int = 1
    var maxCap: Int = 4
    private(set) var activeStrategy: ConcurrencyStrategy = .rorkAISmart
    private(set) var currentReasoning: String = "Initializing..."
    private(set) var factorScores: ConcurrencyFactorScores = ConcurrencyFactorScores(
        memory: .good, memoryMB: 0, network: .good, networkLatencyMs: 0,
        successRate: 0, successLevel: .good, stability: 1.0, stabilityLevel: .good, isBackground: false
    )
    private(set) var decisions: [ConcurrencyDecision] = []
    private(set) var concurrencyHistory: [ConcurrencyHistoryPoint] = []
    private(set) var isActive: Bool = false
    private(set) var isAdjusting: Bool = false

    var userRequestedPairCount: Int = 4
    private(set) var pendingUserPairCount: Int?

    @ObservationIgnored var liveConcurrency: Int { livePairCount }

    private let logger = DebugLogger.shared
    private let crashProtection = CrashProtectionService.shared
    private let toolkit = RorkToolkitService.shared

    // Dynamic memory thresholds from DeviceCapability (replaces hardcoded values)
    private let memoryEmergencyThreshold = DeviceCapability.performanceProfile.memoryThresholdEmergencyMB
    private let memoryCriticalThreshold = DeviceCapability.performanceProfile.memoryThresholdCriticalMB
    private let memoryHighThreshold = DeviceCapability.performanceProfile.memoryThresholdHighMB
    private let memorySoftThreshold = DeviceCapability.performanceProfile.memoryThresholdSoftMB

    private var monitorTask: Task<Void, Never>?
    private var aiAnalysisTask: Task<Void, Never>?

    private var outcomeWindow: [SessionOutcomeRecord] = []
    private let maxOutcomeWindow = 50
    private var latencyWindow: [Int] = []
    private let maxLatencyWindow = 30
    private var consecutiveSuccesses: Int = 0
    private var consecutiveFailures: Int = 0
    private var lastRampUpTime: Date = .distantPast
    private var lastAICallTime: Date = .distantPast
    private var batchStartTime: Date = .distantPast
    private var preEmergencyPairCount: Int?

    private var rampUpCooldownSeconds: TimeInterval { activeStrategy == .conservativeSafe ? 60 : 30 }
    private let aiCallIntervalSeconds: TimeInterval = 30
    private let heuristicCheckIntervalSeconds: TimeInterval = 10
    private var stableSuccessesForRampUp: Int { activeStrategy == .conservativeSafe ? 8 : 4 }

    private var effectiveMaxCap: Int {
        switch activeStrategy {
        case .conservativeSafe: max(1, maxCap / 2)
        default: maxCap
        }
    }

    private struct SessionOutcomeRecord {
        let timestamp: Date
        let wasConclusive: Bool
        let wasTimeout: Bool
        let wasConnectionFailure: Bool
        let latencyMs: Int
    }

    func start(cap: Int, strategy: ConcurrencyStrategy = .rorkAISmart, fixedPairs: Int = 3, liveUserPairs: Int = 4) {
        guard !isActive else { return }
        isActive = true
        activeStrategy = strategy
        maxCap = cap
        preEmergencyPairCount = nil

        switch strategy {
        case .rorkAISmart, .conservativeSafe:
            livePairCount = 1
            currentReasoning = "Starting at 1 pair — warming up"

        case .fullSend:
            livePairCount = cap
            currentReasoning = "Full send — launching at \(cap) pairs"

        case .fixedPairs:
            livePairCount = min(fixedPairs, cap)
            currentReasoning = "Fixed at \(livePairCount) pairs"

        case .liveUserAdjustable:
            livePairCount = min(liveUserPairs, cap)
            userRequestedPairCount = livePairCount
            pendingUserPairCount = nil
            currentReasoning = "User controlled — \(livePairCount) pairs"
        }

        decisions.removeAll()
        concurrencyHistory.removeAll()
        outcomeWindow.removeAll()
        latencyWindow.removeAll()
        consecutiveSuccesses = 0
        consecutiveFailures = 0
        lastRampUpTime = .distantPast
        lastAICallTime = .distantPast
        batchStartTime = Date()

        recordHistoryPoint()
        startMonitoring()
        logger.log("AdaptiveConcurrency: started (strategy=\(strategy.label), cap=\(cap), initial=\(livePairCount) pairs)", category: .automation, level: .info)
    }

    func stop() {
        isActive = false
        monitorTask?.cancel()
        monitorTask = nil
        aiAnalysisTask?.cancel()
        aiAnalysisTask = nil
        pendingUserPairCount = nil
        logger.log("AdaptiveConcurrency: stopped (final=\(livePairCount) pairs, decisions=\(decisions.count))", category: .automation, level: .info)
    }

    func applyPendingUserAdjustment() {
        guard activeStrategy == .liveUserAdjustable, let pending = pendingUserPairCount else { return }
        let clamped = max(1, min(maxCap, pending))
        if clamped != livePairCount {
            applyDecision(newConcurrency: clamped, reasoning: "User adjusted: \(livePairCount) → \(clamped) pairs", wasAI: false)
        }
        pendingUserPairCount = nil
        logger.log("AdaptiveConcurrency: user adjustment applied — now \(livePairCount) pairs", category: .automation, level: .info)
    }

    func setUserRequestedPairs(_ count: Int) {
        guard activeStrategy == .liveUserAdjustable, isActive else { return }
        let clamped = max(1, min(maxCap, count))
        userRequestedPairCount = clamped
        if clamped != livePairCount {
            pendingUserPairCount = clamped
            currentReasoning = "Pending: \(clamped) pairs (after current wave)"
        } else {
            pendingUserPairCount = nil
        }
    }

    func recordOutcome(conclusive: Bool, timeout: Bool = false, connectionFailure: Bool = false, latencyMs: Int = 0) {
        guard isActive else { return }

        let record = SessionOutcomeRecord(
            timestamp: Date(), wasConclusive: conclusive, wasTimeout: timeout,
            wasConnectionFailure: connectionFailure, latencyMs: latencyMs
        )
        outcomeWindow.append(record)
        if outcomeWindow.count > maxOutcomeWindow {
            outcomeWindow.removeFirst(outcomeWindow.count - maxOutcomeWindow)
        }

        if latencyMs > 0 {
            latencyWindow.append(latencyMs)
            if latencyWindow.count > maxLatencyWindow {
                latencyWindow.removeFirst(latencyWindow.count - maxLatencyWindow)
            }
        }

        if conclusive && !timeout && !connectionFailure {
            consecutiveSuccesses += 1
            consecutiveFailures = 0
        } else if timeout || connectionFailure {
            consecutiveFailures += 1
            consecutiveSuccesses = 0

            switch activeStrategy {
            case .conservativeSafe:
                if livePairCount > 1 {
                    immediateRampDown(reason: "Conservative: any failure → immediate ramp-down")
                }
            case .rorkAISmart:
                if consecutiveFailures >= 3 {
                    immediateRampDown(reason: "3+ consecutive failures — reducing pairs")
                }
            case .fullSend, .fixedPairs, .liveUserAdjustable:
                break
            }
        }
    }

    private func immediateRampDown(reason: String) {
        guard livePairCount > 1 else { return }
        let drop: Int
        switch activeStrategy {
        case .conservativeSafe:
            drop = 1
        default:
            drop = consecutiveFailures >= 5 ? 2 : 1
        }
        let newPairs = max(1, livePairCount - drop)
        if newPairs != livePairCount {
            applyDecision(newConcurrency: newPairs, reasoning: reason, wasAI: false)
        }
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive else { return }
                try? await Task.sleep(for: .seconds(self.heuristicCheckIntervalSeconds))
                guard !Task.isCancelled, self.isActive else { return }
                await self.runHeuristicCheck()
            }
        }

        guard activeStrategy.usesAI else { return }
        aiAnalysisTask?.cancel()
        aiAnalysisTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                guard let self, self.isActive else { return }
                if Date().timeIntervalSince(self.lastAICallTime) >= self.aiCallIntervalSeconds {
                    await self.runAIAnalysis()
                    self.lastAICallTime = Date()
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func runHeuristicCheck() async {
        let memMB = crashProtection.currentMemoryUsageMB()
        let isDeathSpiral = crashProtection.isMemoryDeathSpiral
        let growthRate = crashProtection.currentGrowthRateMBPerSec
        let isBackground = UIApplication.shared.applicationState != .active

        let successRate = computeSuccessRate()
        let avgLatency = computeAverageLatency()
        let timeoutRate = computeTimeoutRate()
        let connectionFailureRate = computeConnectionFailureRate()

        let memoryLevel = computeMemoryLevel(memMB: memMB, isDeathSpiral: isDeathSpiral, growthRate: growthRate)
        let networkLevel = computeNetworkLevel(avgLatency: avgLatency, timeoutRate: timeoutRate, connectionFailureRate: connectionFailureRate)
        let successLevel = computeSuccessLevel(successRate: successRate)
        let stability = computeStabilityScore(memMB: memMB, growthRate: growthRate, isDeathSpiral: isDeathSpiral, successRate: successRate, timeoutRate: timeoutRate, connectionFailureRate: connectionFailureRate, isBackground: isBackground)
        let stabilityLevel: ConcurrencyFactorLevel = stability > 0.7 ? .good : (stability > 0.4 ? .warning : .critical)

        factorScores = ConcurrencyFactorScores(
            memory: memoryLevel, memoryMB: memMB,
            network: networkLevel, networkLatencyMs: avgLatency,
            successRate: successRate, successLevel: successLevel,
            stability: stability, stabilityLevel: stabilityLevel,
            isBackground: isBackground
        )
        recordHistoryPoint()

        if isDeathSpiral || memMB > memoryEmergencyThreshold {
            if livePairCount > 1 {
                if preEmergencyPairCount == nil { preEmergencyPairCount = livePairCount }
                applyDecision(newConcurrency: 1, reasoning: "EMERGENCY: Memory death spiral (\(memMB)MB) — dropping to 1 pair", wasAI: false)
            }
            return
        }

        if activeStrategy == .fullSend {
            if let preCrash = preEmergencyPairCount, memMB < memoryCriticalThreshold, !isDeathSpiral {
                preEmergencyPairCount = nil
                applyDecision(newConcurrency: preCrash, reasoning: "Full send: recovered from emergency — restoring \(preCrash) pairs", wasAI: false)
            } else if preEmergencyPairCount == nil && livePairCount < maxCap {
                applyDecision(newConcurrency: maxCap, reasoning: "Full send: restoring to max \(maxCap) pairs", wasAI: false)
            }
            return
        }

        if activeStrategy == .fixedPairs || activeStrategy == .liveUserAdjustable {
            if memMB > memoryCriticalThreshold && livePairCount > 4 {
                if preEmergencyPairCount == nil { preEmergencyPairCount = livePairCount }
                applyDecision(newConcurrency: 4, reasoning: "High memory (\(memMB)MB) — temporary cap at 4 pairs", wasAI: false)
            } else if let preCrash = preEmergencyPairCount, memMB < memoryHighThreshold {
                preEmergencyPairCount = nil
                applyDecision(newConcurrency: preCrash, reasoning: "Memory recovered — restoring \(preCrash) pairs", wasAI: false)
            }
            return
        }

        if memMB > memoryCriticalThreshold && livePairCount > 4 {
            applyDecision(newConcurrency: 4, reasoning: "High memory (\(memMB)MB) — capping at 4 pairs", wasAI: false)
            return
        }

        if isBackground && livePairCount > 2 {
            applyDecision(newConcurrency: max(1, livePairCount - 1), reasoning: "App in background — reducing pairs", wasAI: false)
            return
        }

        if timeoutRate > 0.4 && livePairCount > 1 {
            applyDecision(newConcurrency: max(1, livePairCount - 1), reasoning: "High timeout rate (\(Int(timeoutRate * 100))%) — reducing pairs", wasAI: false)
            return
        }

        if connectionFailureRate > 0.3 && livePairCount > 1 {
            applyDecision(newConcurrency: max(1, livePairCount - 1), reasoning: "Connection failures (\(Int(connectionFailureRate * 100))%) — reducing pairs", wasAI: false)
            return
        }

        let cap = effectiveMaxCap
        let canRampUp = livePairCount < cap
            && consecutiveSuccesses >= stableSuccessesForRampUp
            && Date().timeIntervalSince(lastRampUpTime) >= rampUpCooldownSeconds
            && stability > 0.65
            && !isBackground
            && memMB < memoryHighThreshold
            && timeoutRate < 0.1
            && connectionFailureRate < 0.1

        if canRampUp {
            let newPairs = min(cap, livePairCount + 1)
            applyDecision(
                newConcurrency: newPairs,
                reasoning: "Stable: \(consecutiveSuccesses) successes, memory \(memMB)MB, stability \(String(format: "%.0f", stability * 100))% — ramping to \(newPairs) pairs",
                wasAI: false
            )
            lastRampUpTime = Date()
            consecutiveSuccesses = 0
            return
        }

        if outcomeWindow.count >= 3 {
            let reasonParts: [String] = [
                "\(livePairCount)/\(cap) pairs",
                "mem \(memMB)MB",
                "success \(Int(successRate * 100))%",
                isBackground ? "background" : "foreground"
            ]
            currentReasoning = "Monitoring: " + reasonParts.joined(separator: " · ")
        }
    }

    private func runAIAnalysis() async {
        guard outcomeWindow.count >= 3 else { return }

        let memMB = crashProtection.currentMemoryUsageMB()
        let growthRate = crashProtection.currentGrowthRateMBPerSec
        let isBackground = UIApplication.shared.applicationState != .active
        let successRate = computeSuccessRate()
        let avgLatency = computeAverageLatency()
        let timeoutRate = computeTimeoutRate()
        let connectionFailureRate = computeConnectionFailureRate()
        let elapsedSeconds = Int(Date().timeIntervalSince(batchStartTime))

        let context: [String: Any] = [
            "currentPairs": livePairCount,
            "maxCap": effectiveMaxCap,
            "memoryMB": memMB,
            "memoryGrowthRateMBPerSec": String(format: "%.1f", growthRate),
            "isMemoryDeathSpiral": crashProtection.isMemoryDeathSpiral,
            "isBackground": isBackground,
            "successRate": String(format: "%.0f%%", successRate * 100),
            "avgLatencyMs": avgLatency,
            "timeoutRate": String(format: "%.0f%%", timeoutRate * 100),
            "connectionFailureRate": String(format: "%.0f%%", connectionFailureRate * 100),
            "consecutiveSuccesses": consecutiveSuccesses,
            "consecutiveFailures": consecutiveFailures,
            "totalOutcomes": outcomeWindow.count,
            "elapsedSeconds": elapsedSeconds,
            "secondsSinceLastRampUp": Int(Date().timeIntervalSince(lastRampUpTime)),
            "recentDecisions": decisions.prefix(5).map { ["from": $0.fromConcurrency, "to": $0.toConcurrency, "reasoning": $0.reasoning] }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: context),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        let systemPrompt = """
        You manage adaptive concurrency for a dual-site login testing system on iOS. \
        Concurrency is measured in PAIRS (1 pair = 1 Joe + 1 Ignition webview). \
        The system ALWAYS starts at 1 pair and ramps up cautiously. \
        Analyze the provided metrics and recommend a pair count. \
        RULES: \
        1. Never exceed maxCap. \
        2. Only increase by 1 pair at a time when conditions are stable for 30+ seconds. \
        3. Decrease aggressively (can drop by 2+ pairs) if problems detected. \
        4. If app is in background, prefer lower pairs (max 2). \
        5. Memory above \(memoryCriticalThreshold)MB = max 4 pairs. Death spiral = force 1 pair. \
        6. High timeout or connection failure rates = reduce immediately. \
        7. Prioritize app stability over throughput. \
        Return ONLY JSON: {"pairs":N,"reasoning":"brief explanation"}
        """

        isAdjusting = true

        guard let response = await toolkit.generateText(systemPrompt: systemPrompt, userPrompt: "Current session metrics:\n\(jsonStr)") else {
            isAdjusting = false
            return
        }

        let cleaned = AIResponseCleaner.cleanJSON(response)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let aiPairs = (json["pairs"] as? Int) ?? (json["concurrency"] as? Int) else {
            isAdjusting = false
            return
        }

        let reasoning = (json["reasoning"] as? String) ?? "AI analysis"
        let cap = effectiveMaxCap
        let clamped = max(1, min(cap, aiPairs))

        if clamped > livePairCount && clamped - livePairCount > 1 {
            let conservative = livePairCount + 1
            applyDecision(newConcurrency: conservative, reasoning: "AI: \(reasoning) (capped ramp to +1 pair)", wasAI: true)
        } else if clamped != livePairCount {
            applyDecision(newConcurrency: clamped, reasoning: "AI: \(reasoning)", wasAI: true)
        } else {
            currentReasoning = "AI: \(reasoning) — holding at \(livePairCount) pairs"
        }

        if clamped > livePairCount {
            lastRampUpTime = Date()
            consecutiveSuccesses = 0
        }

        isAdjusting = false
    }

    private func applyDecision(newConcurrency: Int, reasoning: String, wasAI: Bool) {
        let old = livePairCount
        let clamped = max(1, min(maxCap, newConcurrency))
        guard clamped != old else { return }

        livePairCount = clamped
        currentReasoning = reasoning

        let decision = ConcurrencyDecision(
            id: UUID().uuidString,
            timestamp: Date(),
            fromConcurrency: old,
            toConcurrency: clamped,
            reasoning: reasoning,
            wasAI: wasAI,
            memoryMB: crashProtection.currentMemoryUsageMB(),
            successRate: computeSuccessRate(),
            stability: factorScores.stability,
            isBackground: UIApplication.shared.applicationState != .active
        )
        decisions.insert(decision, at: 0)
        if decisions.count > 200 {
            decisions = Array(decisions.prefix(200))
        }

        recordHistoryPoint()

        let level: DebugLogLevel = clamped < old ? .warning : .info
        logger.log("AdaptiveConcurrency: \(old) → \(clamped) pairs [\(wasAI ? "AI" : "heuristic")] — \(reasoning)", category: .automation, level: level)
    }

    private func recordHistoryPoint() {
        concurrencyHistory.append(ConcurrencyHistoryPoint(timestamp: Date(), concurrency: livePairCount))
        if concurrencyHistory.count > 120 {
            concurrencyHistory.removeFirst(concurrencyHistory.count - 120)
        }
    }

    private func computeSuccessRate() -> Double {
        let recent = outcomeWindow.suffix(20)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter(\.wasConclusive).count) / Double(recent.count)
    }

    private func computeAverageLatency() -> Int {
        guard !latencyWindow.isEmpty else { return 0 }
        return latencyWindow.reduce(0, +) / latencyWindow.count
    }

    private func computeTimeoutRate() -> Double {
        let recent = outcomeWindow.suffix(15)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter(\.wasTimeout).count) / Double(recent.count)
    }

    private func computeConnectionFailureRate() -> Double {
        let recent = outcomeWindow.suffix(15)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter(\.wasConnectionFailure).count) / Double(recent.count)
    }

    private func computeMemoryLevel(memMB: Int, isDeathSpiral: Bool, growthRate: Double) -> ConcurrencyFactorLevel {
        if isDeathSpiral || memMB > memoryCriticalThreshold { return .critical }
        if memMB > memoryHighThreshold || growthRate > 20 { return .warning }
        return .good
    }

    private func computeNetworkLevel(avgLatency: Int, timeoutRate: Double, connectionFailureRate: Double) -> ConcurrencyFactorLevel {
        if connectionFailureRate > 0.3 || timeoutRate > 0.3 { return .critical }
        if avgLatency > 25000 || timeoutRate > 0.15 || connectionFailureRate > 0.1 { return .warning }
        return .good
    }

    private func computeSuccessLevel(successRate: Double) -> ConcurrencyFactorLevel {
        if successRate < 0.3 { return .critical }
        if successRate < 0.6 { return .warning }
        return .good
    }

    private func computeStabilityScore(memMB: Int, growthRate: Double, isDeathSpiral: Bool, successRate: Double, timeoutRate: Double, connectionFailureRate: Double, isBackground: Bool) -> Double {
        var score = 1.0

        if isDeathSpiral { score -= 0.5 }
        else if memMB > memoryCriticalThreshold { score -= 0.3 }
        else if memMB > memoryHighThreshold { score -= 0.15 }
        else if memMB > memorySoftThreshold { score -= 0.05 }

        if growthRate > 30 { score -= 0.2 }
        else if growthRate > 15 { score -= 0.1 }

        score -= (1.0 - successRate) * 0.2
        score -= timeoutRate * 0.15
        score -= connectionFailureRate * 0.15

        if isBackground { score -= 0.1 }

        return max(0.0, min(1.0, score))
    }
}
