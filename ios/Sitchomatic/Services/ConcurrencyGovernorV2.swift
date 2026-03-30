import Foundation

// MARK: - Concurrency Governor V2 (M5 Calibrated)

nonisolated struct ConcurrencyTelemetry: Sendable {
    let pairCount: Int
    let successRate: Double
    let avgMemoryDeltaMB: Double
    let avgCompletionTimeMs: Double
    let timestamp: Date
}

nonisolated struct ConcurrencyPreset: Sendable {
    let name: String
    let targetPairs: Int
    let rampUpIntervalSeconds: Double
    let pairsPerRampStep: Int
    let aggressiveMode: Bool

    static let conservative = ConcurrencyPreset(
        name: "Conservative",
        targetPairs: 20,
        rampUpIntervalSeconds: 60,
        pairsPerRampStep: 2,
        aggressiveMode: false
    )

    static let balanced = ConcurrencyPreset(
        name: "Balanced",
        targetPairs: 30,
        rampUpIntervalSeconds: 45,
        pairsPerRampStep: 3,
        aggressiveMode: false
    )

    static let m5Overclock = ConcurrencyPreset(
        name: "M5 Overclock",
        targetPairs: 40,
        rampUpIntervalSeconds: 30,
        pairsPerRampStep: 5,
        aggressiveMode: true
    )
}

@MainActor
final class ConcurrencyGovernorV2 {
    nonisolated(unsafe) static let shared = ConcurrencyGovernorV2()

    private let logger = DebugLogger.shared

    // State
    private(set) var currentPairs: Int = 5
    private(set) var targetPairs: Int = 40
    private(set) var isRampingUp: Bool = false
    private(set) var isRampingDown: Bool = false
    private(set) var currentPreset: ConcurrencyPreset = .m5Overclock

    // Telemetry
    private var telemetry: [ConcurrencyTelemetry] = []
    private let maxTelemetryEntries = 100

    // Ramp-up state
    private var rampUpTask: Task<Void, Never>?
    private var lastRampTime: Date = .distantPast
    private var stabilityWindow: [Bool] = [] // success/failure tracking
    private let stabilityWindowSize = 10

    // Emergency state
    private var emergencyRampDownActive: Bool = false
    private var emergencyRecoveryTask: Task<Void, Never>?

    private init() {
        logger.log("ConcurrencyGovernorV2: initialized with M5 Overclock preset", category: .automation, level: .info)
    }

    // MARK: - Public API

    func startBatch(preset: ConcurrencyPreset = .m5Overclock) {
        currentPreset = preset
        targetPairs = preset.targetPairs
        currentPairs = 5 // Always start conservative
        isRampingUp = true
        isRampingDown = false
        emergencyRampDownActive = false
        stabilityWindow = []

        logger.log("ConcurrencyGovernorV2: batch started — target=\(targetPairs) pairs, ramp=\(Int(preset.rampUpIntervalSeconds))s intervals", category: .automation, level: .info)

        startRampUp()
    }

    func stopBatch() {
        rampUpTask?.cancel()
        rampUpTask = nil
        emergencyRecoveryTask?.cancel()
        emergencyRecoveryTask = nil

        isRampingUp = false
        isRampingDown = false
        emergencyRampDownActive = false

        logger.log("ConcurrencyGovernorV2: batch stopped", category: .automation, level: .info)
    }

    func recordPairResult(success: Bool, memoryDeltaMB: Double, completionTimeMs: Double) {
        // Update stability window
        stabilityWindow.append(success)
        if stabilityWindow.count > stabilityWindowSize {
            stabilityWindow.removeFirst()
        }

        // Record telemetry
        let successRate = Double(stabilityWindow.filter { $0 }.count) / Double(stabilityWindow.count)
        let telemetryEntry = ConcurrencyTelemetry(
            pairCount: currentPairs,
            successRate: successRate,
            avgMemoryDeltaMB: memoryDeltaMB,
            avgCompletionTimeMs: completionTimeMs,
            timestamp: Date()
        )
        telemetry.append(telemetryEntry)

        if telemetry.count > maxTelemetryEntries {
            telemetry.removeFirst(telemetry.count - maxTelemetryEntries)
        }

        logger.log("ConcurrencyGovernorV2: pair result — success=\(success), pairs=\(currentPairs), successRate=\(String(format: "%.0f%%", successRate * 100))", category: .automation, level: .debug)
    }

    func triggerEmergencyRampDown(reason: String) {
        guard !emergencyRampDownActive else { return }

        emergencyRampDownActive = true
        isRampingUp = false
        isRampingDown = true

        let originalPairs = currentPairs
        currentPairs = 10 // Emergency drop to 10 pairs

        logger.log("ConcurrencyGovernorV2: EMERGENCY RAMP-DOWN — \(originalPairs)→\(currentPairs) pairs (reason: \(reason))", category: .automation, level: .warning)

        // Start recovery after stabilization
        emergencyRecoveryTask = Task {
            try? await Task.sleep(for: .seconds(60)) // Wait 1 minute

            guard !Task.isCancelled else { return }

            await startRecovery()
        }
    }

    func getCurrentRecommendedPairs() -> Int {
        currentPairs
    }

    func getStats() -> (current: Int, target: Int, successRate: Double, isStable: Bool) {
        let successRate = stabilityWindow.isEmpty ? 1.0 : Double(stabilityWindow.filter { $0 }.count) / Double(stabilityWindow.count)
        let isStable = successRate >= 0.8 && stabilityWindow.count >= stabilityWindowSize
        return (currentPairs, targetPairs, successRate, isStable)
    }

    func getTelemetry() -> [ConcurrencyTelemetry] {
        telemetry
    }

    func applyPreset(_ preset: ConcurrencyPreset) {
        currentPreset = preset
        targetPairs = preset.targetPairs
        logger.log("ConcurrencyGovernorV2: preset changed to \(preset.name) — target=\(preset.targetPairs) pairs", category: .automation, level: .info)
    }

    // MARK: - Private Implementation

    private func startRampUp() {
        rampUpTask?.cancel()

        rampUpTask = Task {
            while !Task.isCancelled && isRampingUp && currentPairs < targetPairs {
                try? await Task.sleep(for: .seconds(currentPreset.rampUpIntervalSeconds))

                guard !Task.isCancelled && isRampingUp else { break }

                // Check stability before ramping
                if shouldRampUp() {
                    await rampUpStep()
                } else {
                    logger.log("ConcurrencyGovernorV2: ramp-up paused — waiting for stability", category: .automation, level: .info)
                }
            }

            if currentPairs >= targetPairs {
                isRampingUp = false
                logger.log("ConcurrencyGovernorV2: ramp-up COMPLETE — reached target \(targetPairs) pairs", category: .automation, level: .success)
            }
        }
    }

    private func shouldRampUp() -> Bool {
        // Need minimum data points
        guard stabilityWindow.count >= stabilityWindowSize / 2 else { return true }

        // Check success rate
        let successRate = Double(stabilityWindow.filter { $0 }.count) / Double(stabilityWindow.count)
        let threshold: Double = currentPreset.aggressiveMode ? 0.7 : 0.85

        // Check memory pressure
        let memoryProfile = DeviceCapability.performanceProfile
        let (_, _, totalMB) = WebViewMemoryProfiler.shared.getCurrentMemoryUsage()
        let memoryOK = totalMB < Double(memoryProfile.safeMemoryMB) * 0.75

        return successRate >= threshold && memoryOK
    }

    private func rampUpStep() async {
        let previousPairs = currentPairs
        currentPairs = min(currentPairs + currentPreset.pairsPerRampStep, targetPairs)
        lastRampTime = Date()

        logger.log("ConcurrencyGovernorV2: ramp-up step — \(previousPairs)→\(currentPairs) pairs", category: .automation, level: .info)

        // Reset stability window after ramp
        stabilityWindow = []
    }

    private func startRecovery() async {
        guard emergencyRampDownActive else { return }

        logger.log("ConcurrencyGovernorV2: starting recovery from emergency ramp-down", category: .automation, level: .info)

        emergencyRampDownActive = false
        isRampingDown = false
        isRampingUp = true

        // Resume ramp-up with more conservative approach
        let recoveryPreset = ConcurrencyPreset(
            name: "Recovery",
            targetPairs: targetPairs,
            rampUpIntervalSeconds: currentPreset.rampUpIntervalSeconds * 1.5,
            pairsPerRampStep: max(1, currentPreset.pairsPerRampStep / 2),
            aggressiveMode: false
        )
        currentPreset = recoveryPreset

        startRampUp()
    }
}

// MARK: - Concurrency Governor Dashboard View

import SwiftUI
import Charts

struct ConcurrencyGovernorDashboardView: View {
    @State private var governor = ConcurrencyGovernorV2.shared
    @State private var refreshTrigger = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("Concurrency Governor V2")
                    .font(.title2.bold())
                    .padding()

                // Current Stats
                let (current, target, successRate, isStable) = governor.getStats()

                HStack(spacing: 16) {
                    StatCard(
                        title: "Current Pairs",
                        value: "\(current)",
                        subtitle: "of \(target) target",
                        color: current >= target ? .green : .blue
                    )

                    StatCard(
                        title: "Success Rate",
                        value: "\(Int(successRate * 100))%",
                        subtitle: isStable ? "stable" : "stabilizing",
                        color: successRate >= 0.8 ? .green : .orange
                    )

                    StatCard(
                        title: "Status",
                        value: governor.isRampingUp ? "Ramping Up" : "Stable",
                        subtitle: governor.currentPreset.name,
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Telemetry Chart
                let telemetry = governor.getTelemetry()
                if !telemetry.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pair Count & Success Rate Over Time")
                            .font(.headline)
                            .padding(.horizontal)

                        Chart {
                            ForEach(telemetry, id: \.timestamp) { entry in
                                LineMark(
                                    x: .value("Time", entry.timestamp),
                                    y: .value("Pairs", entry.pairCount)
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Time", entry.timestamp),
                                    y: .value("Success %", entry.successRate * 100)
                                )
                                .foregroundStyle(.green)
                            }
                        }
                        .frame(height: 200)
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Preset Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Presets")
                        .font(.headline)

                    HStack(spacing: 12) {
                        PresetButton(preset: .conservative)
                        PresetButton(preset: .balanced)
                        PresetButton(preset: .m5Overclock)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshTrigger.toggle()
            }
        }
    }
}

struct PresetButton: View {
    let preset: ConcurrencyPreset
    @State private var governor = ConcurrencyGovernorV2.shared

    var body: some View {
        Button(action: {
            governor.applyPreset(preset)
        }) {
            VStack(spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                Text("\(preset.targetPairs) pairs")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(governor.currentPreset.name == preset.name ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: governor.currentPreset.name == preset.name ? 2 : 1)
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
