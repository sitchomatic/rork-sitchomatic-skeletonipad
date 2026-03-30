import SwiftUI
import Charts

// MARK: - Stress Test Dashboard View

struct StressTestDashboardView: View {
    @State private var stressTest = StressTestService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusSection
                    presetsSection
                    calibrationSection
                    resultsSection
                }
                .padding()
            }
            .navigationTitle("Stress Test Suite")
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !stressTest.results.isEmpty {
                        Button("Clear", role: .destructive) {
                            stressTest.clearResults()
                        }
                    }
                }
            }
        }
        .withMainMenuButton()
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        if stressTest.isRunning {
            VStack(spacing: 12) {
                HStack {
                    ProgressView()
                        .tint(.teal)
                    Text(stressTest.currentPhase)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(stressTest.progress * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.teal)
                }

                ProgressView(value: stressTest.progress)
                    .tint(.teal)

                HStack {
                    Label("\(stressTest.currentMemoryMB)MB", systemImage: "memorychip")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        stressTest.cancelTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Presets")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

            ForEach(StressTestConfig.allPresets, id: \.pairCount) { config in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.label)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("\(Int(config.durationSeconds))s duration")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if let result = latestResult(for: config.pairCount) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                    }

                    Button("Run") {
                        stressTest.runTest(config: config)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.small)
                    .disabled(stressTest.isRunning)
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(.rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Calibration Section

    private var calibrationSection: some View {
        let cal = stressTest.calibrateThresholds()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Calibration")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

            HStack(spacing: 20) {
                VStack {
                    Text("\(cal.recommendedMaxPairs)")
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(.teal)
                    Text("Max Pairs")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text(String(format: "%.0f", cal.estimatedPerPairMB))
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("MB/Pair")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if !stressTest.results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Results History")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)

                resultChart

                ForEach(stressTest.results) { result in
                    resultRow(result)
                }
            }
        }
    }

    private var resultChart: some View {
        Chart(stressTest.results) { result in
            BarMark(
                x: .value("Pairs", result.pairCount),
                y: .value("Peak MB", result.peakMemoryMB)
            )
            .foregroundStyle(result.passed ? .green : .red)
        }
        .chartXAxisLabel("Pair Count")
        .chartYAxisLabel("Peak Memory (MB)")
        .frame(height: 160)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func resultRow(_ result: StressTestResult) -> some View {
        HStack {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.passed ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.label)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Peak: \(result.peakMemoryMB)MB • Avg: \(result.averageMemoryMB)MB • Pressure: \(result.memoryPressureEvents)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let reason = result.failureReason {
                    Text(reason)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Text(String(format: "%.0fs", result.durationSeconds))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func latestResult(for pairCount: Int) -> StressTestResult? {
        stressTest.results.first(where: { $0.pairCount == pairCount })
    }
}
