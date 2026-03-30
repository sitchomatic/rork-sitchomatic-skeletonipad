import SwiftUI
import Charts

// MARK: - WebViewMemoryProfilerView

struct WebViewMemoryProfilerView: View {
    @State private var vm = WebViewMemoryProfiler.shared

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                waterfallChartSection
                webViewListSection
                recommendationsSection
                actionsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("WebView Memory Profiler")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profilingToggle
            }
        }
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Memory Overview", systemImage: "memorychip")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                if vm.isProfiling {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 20) {
                memoryGauge(
                    title: "Current",
                    valueMB: vm.totalEstimatedMemoryMB,
                    thresholdMB: Double(DeviceCapability.performanceProfile.memoryThresholdSoftMB)
                )
                memoryGauge(
                    title: "Peak",
                    valueMB: vm.peakMemoryMB,
                    thresholdMB: Double(DeviceCapability.performanceProfile.memoryThresholdHighMB)
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(vm.activeSnapshots.count)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("WebViews")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text(vm.diagnosticSummary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Memory Gauge

    @ViewBuilder
    private func memoryGauge(title: String, valueMB: Double, thresholdMB: Double) -> some View {
        VStack(spacing: 4) {
            Gauge(value: min(valueMB, thresholdMB), in: 0...max(thresholdMB, 1)) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.0f", valueMB))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(gaugeGradient(valueMB: valueMB, thresholdMB: thresholdMB))
            .scaleEffect(0.8)

            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(String(format: "%.1f", valueMB)) MB")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func gaugeGradient(valueMB: Double, thresholdMB: Double) -> Gradient {
        let ratio = thresholdMB > 0 ? valueMB / thresholdMB : 0
        if ratio > 0.8 {
            return Gradient(colors: [.orange, .red])
        } else if ratio > 0.5 {
            return Gradient(colors: [.yellow, .orange])
        }
        return Gradient(colors: [.green, .blue])
    }

    // MARK: - Waterfall Chart Section

    @ViewBuilder
    private var waterfallChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Memory Timeline", systemImage: "chart.xyaxis.line")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)

            if vm.waterfallHistory.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "chart.line.downtrend.xyaxis")
                } description: {
                    Text("Start profiling to capture memory timeline data.")
                        .font(.system(.caption, design: .monospaced))
                }
                .frame(height: 180)
            } else {
                Chart(vm.waterfallHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Memory (MB)", point.totalMemoryMB)
                    )
                    .foregroundStyle(.blue.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Memory (MB)", point.totalMemoryMB)
                    )
                    .foregroundStyle(.blue.opacity(0.1).gradient)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Memory (MB)", point.totalMemoryMB)
                    )
                    .symbolSize(point.webViewCount > 0 ? 20 : 8)
                    .foregroundStyle(.blue)
                }
                .chartYAxisLabel("MB")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Per-WebView List

    @ViewBuilder
    private var webViewListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Per-WebView Breakdown", systemImage: "list.bullet.rectangle")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)

            if vm.activeSnapshots.isEmpty {
                Text("No active webview snapshots")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(vm.activeSnapshots.sorted(by: { $0.estimatedMemoryMB > $1.estimatedMemoryMB })) { snapshot in
                    webViewRow(snapshot)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func webViewRow(_ snapshot: WebViewMemorySnapshot) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(snapshot.isActive ? .green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.webViewId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let url = snapshot.url {
                    Text(url)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f MB", snapshot.estimatedMemoryMB))
                    .font(.system(.caption, weight: .semibold, design: .monospaced))
                    .foregroundStyle(memoryColor(mb: snapshot.estimatedMemoryMB))

                Text(snapshot.isActive ? "active" : "idle")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(snapshot.isActive ? .green : .secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func memoryColor(mb: Double) -> Color {
        if mb > 200 { return .red }
        if mb > 100 { return .orange }
        if mb > 50 { return .yellow }
        return .green
    }

    // MARK: - Recommendations Section

    @ViewBuilder
    private var recommendationsSection: some View {
        let recommendations = vm.evictionRecommendations

        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Recommendations", systemImage: "exclamationmark.triangle")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.orange)

                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, recommendation in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)

                        Text(recommendation)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                vm.triggerEviction()
            } label: {
                Label("Evict Now", systemImage: "trash.circle.fill")
                    .font(.system(.body, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                vm.captureWaterfallPoint()
            } label: {
                Label("Capture Snapshot", systemImage: "camera.circle")
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var profilingToggle: some View {
        Button {
            if vm.isProfiling {
                vm.stopProfiling()
            } else {
                vm.startProfiling()
            }
        } label: {
            Image(systemName: vm.isProfiling ? "stop.circle.fill" : "play.circle.fill")
                .foregroundStyle(vm.isProfiling ? .red : .green)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WebViewMemoryProfilerView()
    }
    .preferredColorScheme(.dark)
}
