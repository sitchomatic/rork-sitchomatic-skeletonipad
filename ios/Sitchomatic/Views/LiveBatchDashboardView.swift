import Foundation
import SwiftUI
import Charts

// MARK: - Throughput Data Point

private nonisolated struct ThroughputPoint: Identifiable, Sendable {
    let id: Date
    let timestamp: Date
    let countPerMinute: Double

    init(timestamp: Date, countPerMinute: Double) {
        self.id = timestamp
        self.timestamp = timestamp
        self.countPerMinute = countPerMinute
    }
}

// MARK: - Pair Cell Status

private nonisolated enum PairCellStatus: Sendable {
    case idle
    case active
    case success
    case fail

    var color: Color {
        switch self {
        case .idle: .gray.opacity(0.25)
        case .active: .teal
        case .success: .green
        case .fail: .red
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .active: "Active"
        case .success: "Pass"
        case .fail: "Fail"
        }
    }
}

// MARK: - Live Batch Dashboard View

struct LiveBatchDashboardView: View {
    @State private var pool = WebViewPool.shared
    @State private var engine = AdaptiveConcurrencyEngine.shared
    @State private var governor = AIPredictiveConcurrencyGovernor.shared
    @State private var proxyMonitor = ProxyHealthMonitor.shared
    @State private var loginVM = LoginViewModel.shared
    @State private var ppsrVM = PPSRAutomationViewModel.shared
    @State private var unifiedVM = UnifiedSessionViewModel.shared

    @State private var refreshTick: Int = 0
    @State private var currentMemoryMB: Int = 0
    @State private var throughputHistory: [ThroughputPoint] = []
    @State private var lastCompletedSnapshot: Int = 0
    @State private var lastSnapshotTime: Date = Date()

    private let maxPairs: Int = 40
    private let maxWebViews: Int = 80
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                webViewGaugeSection
                pairStatusGridSection
                throughputChartSection
                networkHealthSection
                aiGovernanceSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Live Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
            currentMemoryMB = MemoryMonitor.currentUsageMB()
            recordThroughputSample()
        }
        .onAppear {
            currentMemoryMB = MemoryMonitor.currentUsageMB()
        }
    }

    // MARK: - 1. WebView Count Gauge + Memory Ring

    private var webViewGaugeSection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "WEBVIEW & MEMORY", icon: "gauge.with.dots.needle.50percent", color: .teal)

            HStack(spacing: 24) {
                // WebView Count Gauge
                webViewGauge
                    .frame(maxWidth: .infinity)

                // Memory Usage Ring
                memoryRing
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private var webViewGauge: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color(.quaternarySystemFill), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Filled arc
                Circle()
                    .trim(from: 0, to: 0.75 * webViewFraction)
                    .stroke(
                        webViewGaugeGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .animation(.easeInOut(duration: 0.5), value: activeWebViewCount)

                VStack(spacing: 2) {
                    Text("\(activeWebViewCount)")
                        .font(.system(.title, design: .monospaced, weight: .black))
                        .foregroundStyle(webViewCountColor)
                        .contentTransition(.numericText())
                    Text("/ \(maxWebViews)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            Text("WEBVIEWS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var memoryRing: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.quaternarySystemFill), lineWidth: 10)

                // Used memory arc
                Circle()
                    .trim(from: 0, to: memoryFraction)
                    .stroke(
                        memoryRingGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: currentMemoryMB)

                VStack(spacing: 2) {
                    Text("\(currentMemoryMB)")
                        .font(.system(.title, design: .monospaced, weight: .black))
                        .foregroundStyle(memoryColor)
                        .contentTransition(.numericText())
                    Text("MB")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            Text("MEMORY")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 2. Per-Pair Status Grid

    private var pairStatusGridSection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "PAIR STATUS GRID", icon: "square.grid.4x3.fill", color: .blue)

            let cellStatuses = computePairStatuses()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

            VStack(spacing: 8) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<maxPairs, id: \.self) { index in
                        pairCell(index: index, status: cellStatuses[index])
                    }
                }

                // Legend
                HStack(spacing: 16) {
                    legendDot(color: .gray.opacity(0.25), label: "Idle")
                    legendDot(color: .teal, label: "Active")
                    legendDot(color: .green, label: "Pass")
                    legendDot(color: .red, label: "Fail")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private func pairCell(index: Int, status: PairCellStatus) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(status.color)
            .frame(height: 28)
            .overlay {
                Text("\(index + 1)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(status == .idle ? .secondary : .white)
            }
            .animation(.easeInOut(duration: 0.3), value: status.label)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - 3. Throughput Chart

    private var throughputChartSection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "THROUGHPUT", icon: "chart.line.uptrend.xyaxis", color: .orange)

            VStack(spacing: 8) {
                if throughputHistory.isEmpty {
                    ContentUnavailableView {
                        Label("No Data Yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Throughput data will appear once a batch is running.")
                    }
                    .frame(height: 180)
                } else {
                    Chart(throughputHistory) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Creds/Min", point.countPerMinute)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Creds/Min", point.countPerMinute)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartYAxisLabel("creds/min")
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute, count: 2)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.minute())
                        }
                    }
                    .frame(height: 180)
                }

                HStack(spacing: 16) {
                    throughputStat(label: "CURRENT", value: currentThroughput, unit: "/min")
                    throughputStat(label: "PEAK", value: peakThroughput, unit: "/min")
                    throughputStat(label: "TOTAL", value: Double(totalCompleted), unit: "")
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private func throughputStat(label: String, value: Double, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(value < 100 ? String(format: "%.1f", value) : "\(Int(value))")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Network Health Panel

    private var networkHealthSection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "NETWORK HEALTH", icon: "network", color: .blue)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Proxy Status
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(proxyStatusColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: proxyMonitor.upstreamHealth.isHealthy ? "checkmark.shield.fill" : "xmark.shield.fill")
                                .font(.body)
                                .foregroundStyle(proxyStatusColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("PROXY")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(proxyMonitor.upstreamHealth.isHealthy ? "Healthy" : "Unhealthy")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(proxyStatusColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Latency
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(latencyColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "clock.fill")
                                .font(.body)
                                .foregroundStyle(latencyColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("LATENCY")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let latencyMs = proxyMonitor.upstreamHealth.latencyMs {
                                Text("\(latencyMs)ms")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(latencyColor)
                                    .contentTransition(.numericText())
                            } else {
                                Text("N/A")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Consecutive Failures
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(failureCountColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.body)
                                .foregroundStyle(failureCountColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("FAILURES")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("\(proxyMonitor.upstreamHealth.consecutiveFailures)")
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(failureCountColor)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Recent health events
                if !proxyMonitor.healthLog.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECENT EVENTS")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)

                        ForEach(proxyMonitor.healthLog.suffix(3)) { event in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(event.isHealthy ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(event.detail)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                if let ms = event.latencyMs {
                                    Text("\(ms)ms")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    // MARK: - 5. AI Governance Panel

    private var aiGovernanceSection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "AI GOVERNANCE", icon: "brain.head.profile.fill", color: .purple)

            VStack(spacing: 12) {
                // Current concurrency + stability
                HStack(spacing: 16) {
                    governanceMetric(
                        label: "CONCURRENCY",
                        value: "\(engine.livePairCount)",
                        sublabel: "of \(engine.maxCap) cap",
                        color: .teal
                    )

                    governanceMetric(
                        label: "STABILITY",
                        value: String(format: "%.0f%%", stabilityScore * 100),
                        sublabel: stabilityLabel,
                        color: stabilityColor
                    )

                    governanceMetric(
                        label: "RECOMMENDED",
                        value: "\(governor.currentRecommendedConcurrency)",
                        sublabel: "pairs",
                        color: .purple
                    )
                }

                // Strategy badge
                HStack(spacing: 8) {
                    Image(systemName: engine.activeStrategy.icon)
                        .font(.caption.bold())
                        .foregroundStyle(engine.activeStrategy.tintColor)
                    Text(engine.activeStrategy.label.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(engine.activeStrategy.tintColor)
                    Spacer()

                    if engine.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(engine.activeStrategy.tintColor.opacity(0.08))
                .clipShape(.rect(cornerRadius: 8))

                // Reasoning
                if !engine.currentReasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REASONING")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(engine.currentReasoning)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Concurrency history chart
                if !engine.concurrencyHistory.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONCURRENCY HISTORY")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Chart(engine.concurrencyHistory.suffix(60), id: \.timestamp) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Pairs", point.concurrency)
                            )
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(.purple)

                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Pairs", point.concurrency)
                            )
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(.purple.opacity(0.15))
                        }
                        .chartYScale(domain: 0...max(engine.maxCap, 1))
                        .frame(height: 100)
                    }
                }

                // Recent decisions
                if !engine.decisions.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT DECISIONS")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)

                        ForEach(engine.decisions.suffix(3)) { decision in
                            HStack(spacing: 6) {
                                Image(systemName: decisionIcon(decision.direction))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(decisionColor(decision.direction))

                                Text("\(decision.fromConcurrency)→\(decision.toConcurrency)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(decisionColor(decision.direction))

                                Text(decision.reasoning)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                if decision.wasAI {
                                    Text("AI")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: .heavy))
                .foregroundStyle(color)
            Spacer()
        }
    }

    private func governanceMetric(label: String, value: String, sublabel: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(sublabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed Properties

    private var activeWebViewCount: Int {
        pool.activeCount
    }

    private var webViewFraction: Double {
        guard maxWebViews > 0 else { return 0 }
        return min(1.0, Double(activeWebViewCount) / Double(maxWebViews))
    }

    private var webViewCountColor: Color {
        let fraction = webViewFraction
        if fraction > 0.85 { return .red }
        if fraction > 0.6 { return .orange }
        return .teal
    }

    private var webViewGaugeGradient: LinearGradient {
        LinearGradient(
            colors: [.teal, webViewFraction > 0.7 ? .orange : .teal, webViewFraction > 0.85 ? .red : .teal],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var totalRAMMB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    }

    private var memoryFraction: Double {
        let emergencyMB = DeviceCapability.performanceProfile.memoryThresholdEmergencyMB
        guard emergencyMB > 0 else { return 0 }
        return min(1.0, Double(currentMemoryMB) / Double(emergencyMB))
    }

    private var memoryColor: Color {
        let fraction = memoryFraction
        if fraction > 0.85 { return .red }
        if fraction > 0.6 { return .orange }
        if fraction > 0.4 { return .yellow }
        return .green
    }

    private var memoryRingGradient: LinearGradient {
        LinearGradient(
            colors: [.green, memoryFraction > 0.5 ? .yellow : .green, memoryFraction > 0.75 ? .red : .green],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var anyBatchRunning: Bool {
        loginVM.isRunning || ppsrVM.isRunning || unifiedVM.isRunning
    }

    private var totalCompleted: Int {
        loginVM.batchCompletedCount + ppsrVM.batchCompletedCount
    }

    private var totalTarget: Int {
        loginVM.batchTotalCount + ppsrVM.batchTotalCount
    }

    private var totalActive: Int {
        loginVM.activeTestCount + ppsrVM.activeTestCount
    }

    private var stabilityScore: Double {
        governor.currentStabilityScore
    }

    private var stabilityLabel: String {
        if stabilityScore >= 0.8 { return "stable" }
        if stabilityScore >= 0.5 { return "caution" }
        return "unstable"
    }

    private var stabilityColor: Color {
        if stabilityScore >= 0.8 { return .green }
        if stabilityScore >= 0.5 { return .yellow }
        return .red
    }

    private var proxyStatusColor: Color {
        proxyMonitor.upstreamHealth.isHealthy ? .green : .red
    }

    private var latencyColor: Color {
        guard let ms = proxyMonitor.upstreamHealth.latencyMs else { return .secondary }
        if ms < 200 { return .green }
        if ms < 500 { return .yellow }
        return .red
    }

    private var failureCountColor: Color {
        let count = proxyMonitor.upstreamHealth.consecutiveFailures
        if count == 0 { return .green }
        if count < 3 { return .yellow }
        return .red
    }

    private var currentThroughput: Double {
        throughputHistory.last?.countPerMinute ?? 0
    }

    private var peakThroughput: Double {
        throughputHistory.map(\.countPerMinute).max() ?? 0
    }

    // MARK: - Status Grid Computation

    private func computePairStatuses() -> [PairCellStatus] {
        var statuses = Array(repeating: PairCellStatus.idle, count: maxPairs)

        // Unified sessions provide the best pair-level data
        let sessions = unifiedVM.sessions
        for (index, session) in sessions.prefix(maxPairs).enumerated() {
            switch session.globalState {
            case .active:
                statuses[index] = .active
            case .success:
                statuses[index] = .success
            case .abortPerm, .abortTemp, .exhausted:
                statuses[index] = .fail
            }
        }

        // If no unified sessions, fall back to active test count
        if sessions.isEmpty {
            let activeCount = totalActive
            for i in 0..<min(activeCount, maxPairs) {
                statuses[i] = .active
            }
            // Mark completed pairs
            let completed = totalCompleted
            let succeeded = loginVM.batchSuccessCount
            let failed = completed - succeeded
            for i in activeCount..<min(activeCount + succeeded, maxPairs) {
                statuses[i] = .success
            }
            for i in min(activeCount + succeeded, maxPairs)..<min(activeCount + succeeded + failed, maxPairs) {
                statuses[i] = .fail
            }
        }

        return statuses
    }

    // MARK: - Throughput Tracking

    private func recordThroughputSample() {
        guard anyBatchRunning else { return }

        let now = Date()
        let currentCompleted = totalCompleted
        let elapsed = now.timeIntervalSince(lastSnapshotTime)

        if elapsed >= 10 {
            let delta = Double(currentCompleted - lastCompletedSnapshot)
            let perMinute = elapsed > 0 ? (delta / elapsed) * 60 : 0

            throughputHistory.append(ThroughputPoint(timestamp: now, countPerMinute: perMinute))

            // Keep last 10 minutes (60 samples at 10s intervals)
            let cutoff = now.addingTimeInterval(-600)
            throughputHistory.removeAll { $0.timestamp < cutoff }

            lastCompletedSnapshot = currentCompleted
            lastSnapshotTime = now
        }
    }

    // MARK: - Decision Helpers

    private func decisionIcon(_ direction: ConcurrencyDecision.ConcurrencyDirection) -> String {
        switch direction {
        case .rampUp: "arrow.up.circle.fill"
        case .rampDown: "arrow.down.circle.fill"
        case .hold: "equal.circle.fill"
        }
    }

    private func decisionColor(_ direction: ConcurrencyDecision.ConcurrencyDirection) -> Color {
        switch direction {
        case .rampUp: .green
        case .rampDown: .red
        case .hold: .yellow
        }
    }
}
