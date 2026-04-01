import Foundation
import SwiftUI

struct FloatingBatchControlBar: View {
    @State private var loginVM = LoginViewModel.shared
    @State private var ppsrVM = PPSRAutomationViewModel.shared
    @State private var unifiedVM = UnifiedSessionViewModel.shared
    @State private var engine = AdaptiveConcurrencyEngine.shared

    @State private var refreshTick: Int = 0
    @State private var isExpanded: Bool = true
    @State private var concurrencyValue: Double = 4

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isAnyRunning: Bool {
        loginVM.isRunning || ppsrVM.isRunning || unifiedVM.isRunning
    }

    private var isAnyPaused: Bool {
        loginVM.isPaused || ppsrVM.isPaused || unifiedVM.isPaused
    }

    private var isAnyStopping: Bool {
        loginVM.isStopping || ppsrVM.isStopping || unifiedVM.isStopping
    }

    var body: some View {
        if isAnyRunning {
            VStack(spacing: 0) {
                if isExpanded {
                    expandedBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedPill
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.15), value: isExpanded)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onReceive(refreshTimer) { _ in
                refreshTick += 1
            }
            .onAppear {
                concurrencyValue = Double(engine.livePairCount)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isAnyPaused)
            .sensoryFeedback(.warning, trigger: isAnyStopping)
        }
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        Button {
            withAnimation { isExpanded = true }
        } label: {
            HStack(spacing: 8) {
                statusIndicator
                    .frame(width: 8, height: 8)

                Text(activeSiteLabel)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)

                Text("\(completedCount)/\(totalCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())

                progressBar
                    .frame(width: 40, height: 4)

                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(statusColor.opacity(0.2))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    // MARK: - Expanded Bar

    private var expandedBar: some View {
        VStack(spacing: 10) {
            // Header row with collapse button
            HStack {
                HStack(spacing: 6) {
                    statusIndicator
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(statusColor)
                }

                Spacer()

                // Elapsed time
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .bold))
                    Text(elapsedTimeString)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white.opacity(0.6))

                Button {
                    withAnimation { isExpanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            // Progress row
            VStack(spacing: 6) {
                HStack {
                    Text("\(completedCount) / \(totalCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Spacer()

                    if let eta = estimatedTimeRemaining {
                        HStack(spacing: 3) {
                            Text("ETA")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(eta)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .contentTransition(.numericText())
                        }
                    }

                    Text(String(format: "%.0f%%", batchProgress * 100))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * batchProgress)
                            .animation(.easeInOut(duration: 0.3), value: batchProgress)
                    }
                }
                .frame(height: 6)
            }

            // Concurrency slider
            VStack(spacing: 4) {
                HStack {
                    Text("PAIRS")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("\(Int(concurrencyValue))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.teal)
                        .contentTransition(.numericText())
                }

                Slider(value: $concurrencyValue, in: 1...40, step: 1)
                    .tint(.teal)
                    .onChange(of: concurrencyValue) { _, newValue in
                        engine.setUserRequestedPairs(Int(newValue))
                    }
                    .sensoryFeedback(.selection, trigger: Int(concurrencyValue))
            }

            // Control buttons
            HStack(spacing: 8) {
                if isAnyPaused {
                    controlButton(icon: "play.fill", label: "RESUME", hint: "⌘R", color: .green) {
                        resumeAll()
                    }
                } else {
                    controlButton(icon: "pause.fill", label: "PAUSE", hint: "⌘P", color: .orange) {
                        pauseAll()
                    }
                    .disabled(isAnyStopping)
                }

                controlButton(icon: "stop.fill", label: "STOP", hint: "⌘.", color: .red) {
                    stopAll()
                }
                .disabled(isAnyStopping)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    // MARK: - Control Button

    private func controlButton(icon: String, label: String, hint: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                Text(hint)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(color.opacity(0.5))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Components

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .shadow(color: statusColor.opacity(0.6), radius: 4)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(statusColor)
                    .frame(width: geo.size.width * batchProgress)
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if isAnyStopping { return .red }
        if isAnyPaused { return .orange }
        return .green
    }

    private var statusLabel: String {
        if isAnyStopping { return "STOPPING" }
        if isAnyPaused { return "PAUSED" }
        return "RUNNING"
    }

    private var activeSiteLabel: String {
        if unifiedVM.isRunning { return "UNIFIED" }
        if loginVM.isRunning { return loginVM.batchSiteLabel.isEmpty ? "LOGIN" : loginVM.batchSiteLabel.uppercased() }
        if ppsrVM.isRunning { return "PPSR" }
        return "BATCH"
    }

    private var completedCount: Int {
        if unifiedVM.isRunning {
            return unifiedVM.sessions.filter(\.isTerminal).count
        }
        return loginVM.batchCompletedCount + ppsrVM.batchCompletedCount
    }

    private var totalCount: Int {
        if unifiedVM.isRunning {
            return unifiedVM.sessions.count
        }
        return loginVM.batchTotalCount + ppsrVM.batchTotalCount
    }

    private var batchProgress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1.0, Double(completedCount) / Double(totalCount))
    }

    private var elapsedTimeString: String {
        if unifiedVM.isRunning {
            return unifiedVM.batchElapsed
        }
        if let start = loginVM.batchStartTime {
            let d = Date().timeIntervalSince(start)
            if d < 60 { return String(format: "%.0fs", d) }
            return String(format: "%.0fm %02.0fs", (d / 60).rounded(.down), d.truncatingRemainder(dividingBy: 60))
        }
        return "—"
    }

    private var estimatedTimeRemaining: String? {
        guard completedCount > 0, totalCount > completedCount else { return nil }
        let start: Date?
        if unifiedVM.isRunning {
            start = unifiedVM.batchStartTime
        } else {
            start = loginVM.batchStartTime
        }
        guard let startTime = start else { return nil }

        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 5 else { return nil }

        let rate = elapsed / Double(completedCount)
        let remaining = rate * Double(totalCount - completedCount)

        if remaining < 60 { return String(format: "%.0fs", remaining) }
        if remaining < 3600 { return String(format: "%.0fm", remaining / 60) }
        return String(format: "%.0fh %.0fm", (remaining / 3600).rounded(.down), (remaining.truncatingRemainder(dividingBy: 3600)) / 60)
    }

    private var batchStartTime: Date? {
        loginVM.batchStartTime ?? unifiedVM.batchStartTime
    }

    // MARK: - Actions

    private func pauseAll() {
        if loginVM.isRunning { loginVM.pauseQueue() }
        if ppsrVM.isRunning { ppsrVM.pauseQueue() }
        if unifiedVM.isRunning { unifiedVM.pauseBatch() }
    }

    private func resumeAll() {
        if loginVM.isRunning { loginVM.resumeQueue() }
        if ppsrVM.isRunning { ppsrVM.resumeQueue() }
        if unifiedVM.isRunning { unifiedVM.resumeBatch() }
    }

    private func stopAll() {
        if loginVM.isRunning { loginVM.stopQueue() }
        if ppsrVM.isRunning { ppsrVM.stopQueue() }
        if unifiedVM.isRunning { unifiedVM.stopBatch() }
    }
}

// MARK: - View Modifier for Easy Attachment

struct FloatingBatchControlBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                FloatingBatchControlBar()
            }
    }
}

extension View {
    func withFloatingBatchControlBar() -> some View {
        modifier(FloatingBatchControlBarModifier())
    }
}
