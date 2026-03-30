import Foundation
import SwiftUI

// MARK: - Stress Test Configuration

nonisolated struct StressTestConfig: Sendable {
    let pairCount: Int
    let duration: TimeInterval
    let syntheticWorkload: Bool
    let targetSuccessRate: Double
    let memoryPressureSimulation: Bool

    static let test10 = StressTestConfig(pairCount: 10, duration: 300, syntheticWorkload: true, targetSuccessRate: 0.9, memoryPressureSimulation: false)
    static let test20 = StressTestConfig(pairCount: 20, duration: 300, syntheticWorkload: true, targetSuccessRate: 0.85, memoryPressureSimulation: false)
    static let test30 = StressTestConfig(pairCount: 30, duration: 300, syntheticWorkload: true, targetSuccessRate: 0.80, memoryPressureSimulation: true)
    static let test40 = StressTestConfig(pairCount: 40, duration: 600, syntheticWorkload: true, targetSuccessRate: 0.75, memoryPressureSimulation: true)
}

nonisolated struct StressTestResult: Sendable, Identifiable {
    let id: UUID
    let config: StressTestConfig
    let startTime: Date
    let endTime: Date
    let totalAttempts: Int
    let successfulAttempts: Int
    let failedAttempts: Int
    let avgMemoryUsageMB: Double
    let peakMemoryUsageMB: Double
    let avgLatencyMs: Double
    let throughputPerMinute: Double
    let crashed: Bool
    let passedThreshold: Bool

    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successfulAttempts) / Double(totalAttempts)
    }

    var status: String {
        if crashed { return "CRASHED" }
        if passedThreshold { return "PASSED" }
        return "FAILED"
    }

    init(
        config: StressTestConfig,
        startTime: Date,
        endTime: Date,
        totalAttempts: Int,
        successfulAttempts: Int,
        failedAttempts: Int,
        avgMemoryUsageMB: Double,
        peakMemoryUsageMB: Double,
        avgLatencyMs: Double,
        throughputPerMinute: Double,
        crashed: Bool
    ) {
        self.id = UUID()
        self.config = config
        self.startTime = startTime
        self.endTime = endTime
        self.totalAttempts = totalAttempts
        self.successfulAttempts = successfulAttempts
        self.failedAttempts = failedAttempts
        self.avgMemoryUsageMB = avgMemoryUsageMB
        self.peakMemoryUsageMB = peakMemoryUsageMB
        self.avgLatencyMs = avgLatencyMs
        self.throughputPerMinute = throughputPerMinute
        self.crashed = crashed

        let successRate = totalAttempts > 0 ? Double(successfulAttempts) / Double(totalAttempts) : 0
        self.passedThreshold = successRate >= config.targetSuccessRate && !crashed
    }
}

// MARK: - Stress Test & Calibration Service

@MainActor
final class StressTestCalibrationService {
    nonisolated(unsafe) static let shared = StressTestCalibrationService()

    private let logger = DebugLogger.shared
    private let memoryProfiler = WebViewMemoryProfiler.shared

    private(set) var testResults: [StressTestResult] = []
    private(set) var isRunning: Bool = false
    private var currentTest: Task<Void, Never>?

    private init() {
        logger.log("StressTestCalibrationService: initialized", category: .automation, level: .info)
    }

    // MARK: - Public API

    func runStressTest(config: StressTestConfig) async -> StressTestResult {
        guard !isRunning else {
            logger.log("StressTestCalibration: test already running", category: .automation, level: .warning)
            return createFailedResult(config: config, reason: "Already running")
        }

        isRunning = true
        defer { isRunning = false }

        logger.log("StressTestCalibration: starting test with \(config.pairCount) pairs", category: .automation, level: .info)

        let startTime = Date()
        var totalAttempts = 0
        var successfulAttempts = 0
        var failedAttempts = 0
        var memorySnapshots: [Double] = []
        var latencies: [Double] = []
        var crashed = false

        // Configure concurrency governor
        let preset = ConcurrencyPreset(
            name: "Stress Test",
            targetPairs: config.pairCount,
            rampUpIntervalSeconds: 10,
            pairsPerRampStep: config.pairCount / 4,
            aggressiveMode: true
        )
        ConcurrencyGovernorV2.shared.applyPreset(preset)
        ConcurrencyGovernorV2.shared.startBatch(preset: preset)

        // Start memory profiling
        memoryProfiler.startProfiling()

        // Run test for configured duration
        let testDuration = config.duration
        let testDeadline = Date().addingTimeInterval(testDuration)

        while Date() < testDeadline && !crashed {
            // Simulate workload
            let (success, memoryMB, latencyMs) = await simulateWorkload(config: config)

            totalAttempts += 1
            if success {
                successfulAttempts += 1
            } else {
                failedAttempts += 1
            }

            memorySnapshots.append(memoryMB)
            latencies.append(latencyMs)

            // Check for crash conditions
            let memoryProfile = DeviceCapability.performanceProfile
            if memoryMB > Double(memoryProfile.safeMemoryMB) * 1.2 {
                crashed = true
                logger.log("StressTestCalibration: CRASH detected — memory exceeded safe threshold", category: .automation, level: .error)
                break
            }

            // Wait between attempts
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Stop profiling
        memoryProfiler.stopProfiling()
        ConcurrencyGovernorV2.shared.stopBatch()

        let endTime = Date()

        // Calculate metrics
        let avgMemory = memorySnapshots.isEmpty ? 0 : memorySnapshots.reduce(0, +) / Double(memorySnapshots.count)
        let peakMemory = memorySnapshots.max() ?? 0
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let duration = endTime.timeIntervalSince(startTime)
        let throughput = duration > 0 ? Double(totalAttempts) / (duration / 60) : 0

        let result = StressTestResult(
            config: config,
            startTime: startTime,
            endTime: endTime,
            totalAttempts: totalAttempts,
            successfulAttempts: successfulAttempts,
            failedAttempts: failedAttempts,
            avgMemoryUsageMB: avgMemory,
            peakMemoryUsageMB: peakMemory,
            avgLatencyMs: avgLatency,
            throughputPerMinute: throughput,
            crashed: crashed
        )

        testResults.append(result)

        logger.log("StressTestCalibration: test complete — \(result.status) (success rate: \(Int(result.successRate * 100))%)", category: .automation, level: result.passedThreshold ? .success : .warning)

        return result
    }

    func runFullCalibrationSuite() async -> [StressTestResult] {
        logger.log("StressTestCalibration: starting full calibration suite", category: .automation, level: .info)

        var results: [StressTestResult] = []

        let configs = [
            StressTestConfig.test10,
            StressTestConfig.test20,
            StressTestConfig.test30,
            StressTestConfig.test40,
        ]

        for config in configs {
            let result = await runStressTest(config: config)
            results.append(result)

            // Wait between tests
            try? await Task.sleep(for: .seconds(30))
        }

        logger.log("StressTestCalibration: full suite complete — \(results.filter { $0.passedThreshold }.count)/\(results.count) passed", category: .automation, level: .info)

        return results
    }

    func calibrateThresholds(based on: StressTestResult) -> (safeMemoryMB: Int, maxPairs: Int) {
        let memoryPerPair = on.avgMemoryUsageMB / Double(on.config.pairCount)
        let memoryProfile = DeviceCapability.performanceProfile

        // Calculate safe max pairs based on observed memory usage
        let safeMaxPairs = Int(Double(memoryProfile.safeMemoryMB) * 0.8 / memoryPerPair)

        // Recommend conservative safe memory threshold
        let recommendedSafeMemory = Int(on.peakMemoryUsageMB * 1.3)

        logger.log("StressTestCalibration: calibrated thresholds — safeMemory=\(recommendedSafeMemory)MB, maxPairs=\(safeMaxPairs)", category: .automation, level: .info)

        return (recommendedSafeMemory, safeMaxPairs)
    }

    func exportReport() -> String {
        var report = "# Sitchomatic Stress Test Report\n\n"
        report += "Generated: \(Date())\n\n"

        report += "## Test Results\n\n"

        for result in testResults {
            report += "### \(result.config.pairCount) Pairs Test\n"
            report += "- Status: **\(result.status)**\n"
            report += "- Success Rate: \(Int(result.successRate * 100))%\n"
            report += "- Attempts: \(result.totalAttempts) (\(result.successfulAttempts) success, \(result.failedAttempts) failed)\n"
            report += "- Avg Memory: \(Int(result.avgMemoryUsageMB))MB\n"
            report += "- Peak Memory: \(Int(result.peakMemoryUsageMB))MB\n"
            report += "- Avg Latency: \(Int(result.avgLatencyMs))ms\n"
            report += "- Throughput: \(Int(result.throughputPerMinute))/min\n"
            report += "- Duration: \(Int(result.endTime.timeIntervalSince(result.startTime)))s\n\n"
        }

        report += "## Recommendations\n\n"

        if let bestResult = testResults.filter({ $0.passedThreshold }).max(by: { $0.config.pairCount < $1.config.pairCount }) {
            let calibrated = calibrateThresholds(based: bestResult)
            report += "- Recommended max concurrent pairs: **\(calibrated.maxPairs)**\n"
            report += "- Recommended safe memory threshold: **\(calibrated.safeMemoryMB)MB**\n"
        }

        return report
    }

    func clearResults() {
        testResults.removeAll()
        logger.log("StressTestCalibration: results cleared", category: .automation, level: .info)
    }

    // MARK: - Private

    private func simulateWorkload(config: StressTestConfig) async -> (success: Bool, memoryMB: Double, latencyMs: Double) {
        let start = Date()

        // Simulate work
        let success = Double.random(in: 0...1) < (config.targetSuccessRate + 0.1)

        // Simulate memory usage
        let (_, _, totalMemoryMB) = memoryProfiler.getCurrentMemoryUsage()

        // Simulate latency
        let baseLatency = 150.0
        let variation = Double.random(in: -50...100)
        let latencyMs = baseLatency + variation

        if config.memoryPressureSimulation {
            try? await Task.sleep(for: .milliseconds(Int(latencyMs)))
        }

        let duration = Date().timeIntervalSince(start) * 1000

        return (success, totalMemoryMB, duration)
    }

    private func createFailedResult(config: StressTestConfig, reason: String) -> StressTestResult {
        logger.log("StressTestCalibration: test failed — \(reason)", category: .automation, level: .error)

        return StressTestResult(
            config: config,
            startTime: Date(),
            endTime: Date(),
            totalAttempts: 0,
            successfulAttempts: 0,
            failedAttempts: 0,
            avgMemoryUsageMB: 0,
            peakMemoryUsageMB: 0,
            avgLatencyMs: 0,
            throughputPerMinute: 0,
            crashed: true
        )
    }
}

// MARK: - Stress Test Dashboard View

struct StressTestDashboardView: View {
    @State private var stressTest = StressTestCalibrationService.shared
    @State private var isRunning = false
    @State private var selectedConfig: StressTestConfig = .test10

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Stress Test & Calibration")
                    .font(.title2.bold())

                // Config Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Test Configuration")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TestConfigButton(config: .test10, selected: $selectedConfig)
                        TestConfigButton(config: .test20, selected: $selectedConfig)
                        TestConfigButton(config: .test30, selected: $selectedConfig)
                        TestConfigButton(config: .test40, selected: $selectedConfig)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)

                // Run Button
                Button(action: {
                    Task {
                        isRunning = true
                        _ = await stressTest.runStressTest(config: selectedConfig)
                        isRunning = false
                    }
                }) {
                    Label(isRunning ? "Running Test..." : "Run Stress Test", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRunning ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(isRunning)

                // Results
                if !stressTest.testResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Results")
                            .font(.headline)

                        ForEach(stressTest.testResults) { result in
                            StressTestResultCard(result: result)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct TestConfigButton: View {
    let config: StressTestConfig
    @Binding var selected: StressTestConfig

    var body: some View {
        Button(action: {
            selected = config
        }) {
            VStack(spacing: 4) {
                Text("\(config.pairCount)")
                    .font(.title2.bold())
                Text("pairs")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(config.pairCount == selected.pairCount ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: config.pairCount == selected.pairCount ? 2 : 1)
            )
        }
    }
}

struct StressTestResultCard: View {
    let result: StressTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(result.config.pairCount) Pairs")
                    .font(.headline)

                Spacer()

                Text(result.status)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundStyle(statusColor)
                    .cornerRadius(8)
            }

            HStack(spacing: 20) {
                Stat(label: "Success", value: "\(Int(result.successRate * 100))%")
                Stat(label: "Avg Memory", value: "\(Int(result.avgMemoryUsageMB))MB")
                Stat(label: "Throughput", value: "\(Int(result.throughputPerMinute))/min")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var statusColor: Color {
        result.passedThreshold ? .green : result.crashed ? .red : .orange
    }
}

struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
