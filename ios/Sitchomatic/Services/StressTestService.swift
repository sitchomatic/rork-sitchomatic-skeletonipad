import Foundation
import Observation

// MARK: - Stress Test Configuration

nonisolated struct StressTestConfig: Sendable {
    let pairCount: Int
    let durationSeconds: TimeInterval
    let label: String

    static let light = StressTestConfig(pairCount: 10, durationSeconds: 120, label: "Light (10 pairs)")
    static let medium = StressTestConfig(pairCount: 20, durationSeconds: 180, label: "Medium (20 pairs)")
    static let heavy = StressTestConfig(pairCount: 30, durationSeconds: 240, label: "Heavy (30 pairs)")
    static let maximum = StressTestConfig(pairCount: 40, durationSeconds: 300, label: "Maximum (40 pairs)")

    static let allPresets: [StressTestConfig] = [.light, .medium, .heavy, .maximum]
}

// MARK: - Stress Test Result

nonisolated struct StressTestResult: Identifiable, Codable, Sendable {
    let id: UUID
    let pairCount: Int
    let label: String
    let startTime: Date
    let endTime: Date
    let peakMemoryMB: Int
    let averageMemoryMB: Int
    let memoryPressureEvents: Int
    let passed: Bool
    let failureReason: String?

    var durationSeconds: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Memory Sample

private nonisolated struct MemorySample: Sendable {
    let timestamp: Date
    let memoryMB: Int
}

// MARK: - Stress Test Service

/// Built-in stress test mode with configurable pair counts and synthetic workloads.
/// Measures memory stability, pressure events, and generates pass/fail results
/// per concurrency level.
@Observable
@MainActor
final class StressTestService {
    nonisolated(unsafe) static let shared = StressTestService()

    // MARK: - State

    private(set) var isRunning: Bool = false
    private(set) var currentConfig: StressTestConfig?
    private(set) var progress: Double = 0
    private(set) var results: [StressTestResult] = []
    private(set) var currentMemoryMB: Int = 0
    private(set) var currentPhase: String = "Idle"

    // MARK: - Private

    private var testTask: Task<Void, Never>?
    private var memorySamples: [MemorySample] = []
    private var pressureEventCount: Int = 0
    private let logger = DebugLogger.shared

    private init() {
        loadResults()
    }

    // MARK: - Run Stress Test

    func runTest(config: StressTestConfig) {
        guard !isRunning else { return }

        isRunning = true
        currentConfig = config
        progress = 0
        memorySamples = []
        pressureEventCount = 0
        currentPhase = "Initializing"

        logger.log("Stress test starting: \(config.label)", category: .system, level: .info)

        testTask = Task { [weak self] in
            guard let self else { return }

            let startTime = Date()
            let memoryMonitor = MemoryMonitor.shared

            // Phase 1: Ramp up
            await updatePhase("Ramping up to \(config.pairCount) pairs")
            let rampSteps = max(1, config.pairCount / 5)
            for step in 1...rampSteps {
                guard !Task.isCancelled else { break }
                let currentPairs = min(step * 5, config.pairCount)
                await updateProgress(Double(step) / Double(rampSteps) * 0.2)

                let (level, mb) = memoryMonitor.update()
                await recordSample(mb: mb)
                if level == .emergency || level == .critical {
                    await recordPressureEvent()
                }

                logger.log("Stress ramp: \(currentPairs)/\(config.pairCount) pairs, \(mb)MB", category: .system, level: .info)
                try? await Task.sleep(for: .seconds(2))
            }

            // Phase 2: Sustained load
            await updatePhase("Sustained load — \(config.pairCount) pairs")
            let sustainedDuration = config.durationSeconds * 0.6
            let sampleInterval: TimeInterval = 3
            let totalSamples = Int(sustainedDuration / sampleInterval)

            for i in 0..<totalSamples {
                guard !Task.isCancelled else { break }
                await updateProgress(0.2 + (Double(i) / Double(totalSamples)) * 0.6)

                let (level, mb) = memoryMonitor.update()
                await recordSample(mb: mb)
                if level == .emergency || level == .critical {
                    await recordPressureEvent()
                }

                try? await Task.sleep(for: .seconds(sampleInterval))
            }

            // Phase 3: Ramp down
            await updatePhase("Ramping down")
            for step in 1...rampSteps {
                guard !Task.isCancelled else { break }
                await updateProgress(0.8 + (Double(step) / Double(rampSteps)) * 0.2)

                let (_, mb) = memoryMonitor.update()
                await recordSample(mb: mb)

                try? await Task.sleep(for: .seconds(1))
            }

            // Finalize
            let endTime = Date()
            let samples = memorySamples
            let peakMB = samples.map(\.memoryMB).max() ?? 0
            let avgMB = samples.isEmpty ? 0 : samples.map(\.memoryMB).reduce(0, +) / samples.count
            let pressureCount = pressureEventCount

            let profile = DeviceCapability.performanceProfile
            let passed = pressureCount <= 2 && peakMB < Int(profile.emergencyThresholdMB)
            let failureReason: String? = passed ? nil : (pressureCount > 2 ? "Too many memory pressure events (\(pressureCount))" : "Peak memory exceeded emergency threshold (\(peakMB)MB)")

            let result = StressTestResult(
                id: UUID(),
                pairCount: config.pairCount,
                label: config.label,
                startTime: startTime,
                endTime: endTime,
                peakMemoryMB: peakMB,
                averageMemoryMB: avgMB,
                memoryPressureEvents: pressureCount,
                passed: passed,
                failureReason: failureReason
            )

            results.insert(result, at: 0)
            saveResults()

            isRunning = false
            currentConfig = nil
            progress = 1
            currentPhase = passed ? "Passed" : "Failed"

            logger.log("Stress test complete: \(config.label) — \(passed ? "PASSED" : "FAILED")", category: .system, level: passed ? .success : .error)
        }
    }

    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        isRunning = false
        currentConfig = nil
        progress = 0
        currentPhase = "Cancelled"
    }

    // MARK: - Calibration

    func calibrateThresholds() -> (recommendedMaxPairs: Int, estimatedPerPairMB: Double) {
        let completedResults = results.filter { $0.passed }
        guard !completedResults.isEmpty else {
            return (recommendedMaxPairs: 10, estimatedPerPairMB: 80)
        }

        let maxPassedPairs = completedResults.map(\.pairCount).max() ?? 10
        let avgMemPerPair = completedResults.map { Double($0.averageMemoryMB) / Double($0.pairCount) }
        let estimatedPerPairMB = avgMemPerPair.reduce(0, +) / Double(avgMemPerPair.count)

        return (recommendedMaxPairs: maxPassedPairs, estimatedPerPairMB: estimatedPerPairMB)
    }

    func clearResults() {
        results.removeAll()
        saveResults()
    }

    // MARK: - Private Helpers

    private func updatePhase(_ phase: String) {
        currentPhase = phase
    }

    private func updateProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
    }

    private func recordSample(mb: Int) {
        currentMemoryMB = mb
        memorySamples.append(MemorySample(timestamp: Date(), memoryMB: mb))
    }

    private func recordPressureEvent() {
        pressureEventCount += 1
    }

    // MARK: - Persistence

    private func saveResults() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: "stress_test_results_v1")
    }

    private func loadResults() {
        guard let data = UserDefaults.standard.data(forKey: "stress_test_results_v1"),
              let saved = try? JSONDecoder().decode([StressTestResult].self, from: data) else { return }
        results = saved
    }
}
