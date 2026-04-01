import SwiftUI

struct ConcurrencyCapSelector: View {
    @Bindable var engine: AdaptiveConcurrencyEngine
    let isRunning: Bool

    private let presets: [(label: String, value: Int)] = [
        ("2", 2), ("4", 4), ("6", 6), ("8", 8), ("10", 10)
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: engine.activeStrategy.icon)
                    .font(.caption.bold())
                    .foregroundStyle(engine.activeStrategy.tintColor)
                Text("MAX PAIR CAP")
                    .font(.system(.caption, design: .monospaced, weight: .heavy))
                    .foregroundStyle(engine.activeStrategy.tintColor)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: engine.activeStrategy.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(engine.activeStrategy.tintColor)
                    Text(engine.activeStrategy.label.uppercased())
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(engine.activeStrategy.tintColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(engine.activeStrategy.tintColor.opacity(0.12))
                .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.value) { preset in
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            engine.maxCap = preset.value
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(engine.maxCap == preset.value ? engine.activeStrategy.tintColor : Color(.tertiarySystemFill))
                            .foregroundStyle(engine.maxCap == preset.value ? .black : .primary)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .disabled(isRunning)
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: engine.maxCap)

            Text("Starts at 1 pair (1 Joe + 1 Ignition) and ramps up to this cap")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }
}

struct LiveUserPairSlider: View {
    @Bindable var engine: AdaptiveConcurrencyEngine

    private let stops = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Text("LIVE PAIR CONTROL")
                    .font(.system(.caption, design: .monospaced, weight: .heavy))
                    .foregroundStyle(.purple)
                Spacer()

                if let pending = engine.pendingUserPairCount {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                        Text("PENDING: \(pending)")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(spacing: 6) {
                Text("\(engine.livePairCount)")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.purple)
                    .contentTransition(.numericText())
                    .frame(width: 36)

                Text("pair\(engine.livePairCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        let current = engine.userRequestedPairCount
                        if current > 1 {
                            withAnimation(.spring(duration: 0.2)) {
                                engine.setUserRequestedPairs(current - 1)
                            }
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.bold())
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .disabled(engine.userRequestedPairCount <= 1)

                    Text("\(engine.userRequestedPairCount)")
                        .font(.system(.headline, design: .monospaced, weight: .bold))
                        .foregroundStyle(.purple)
                        .frame(width: 30)
                        .contentTransition(.numericText())

                    Button {
                        let current = engine.userRequestedPairCount
                        if current < engine.maxCap {
                            withAnimation(.spring(duration: 0.2)) {
                                engine.setUserRequestedPairs(current + 1)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .disabled(engine.userRequestedPairCount >= engine.maxCap)
                }
            }

            GeometryReader { geo in
                let filledWidth = geo.size.width * CGFloat(engine.livePairCount) / CGFloat(max(1, engine.maxCap))
                let requestedWidth = geo.size.width * CGFloat(engine.userRequestedPairCount) / CGFloat(max(1, engine.maxCap))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.quaternarySystemFill))
                    if engine.pendingUserPairCount != nil {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: requestedWidth)
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .purple.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: filledWidth)
                }
            }
            .frame(height: 8)
            .clipShape(.rect(cornerRadius: 6))

            Text("Changes apply after current wave completes")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
        .sensoryFeedback(.impact(weight: .light), trigger: engine.userRequestedPairCount)
        .animation(.spring(duration: 0.3), value: engine.pendingUserPairCount)
    }
}

struct AdaptiveConcurrencyDashboardView: View {
    let engine: AdaptiveConcurrencyEngine
    @State private var showHistory: Bool = false

    private var strategyColor: Color { engine.activeStrategy.tintColor }

    var body: some View {
        VStack(spacing: 10) {
            if engine.activeStrategy.isUserControlled {
                LiveUserPairSlider(engine: engine)
            }

            Button { showHistory = true } label: {
                VStack(spacing: 10) {
                    pairCountHeader
                    reasoningLine
                    sparklineGraph
                    factorBadges
                }
                .padding(14)
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showHistory) {
                ConcurrencyHistorySheet(engine: engine)
            }
        }
    }

    private var pairCountHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: engine.activeStrategy.icon)
                    .font(.caption)
                    .foregroundStyle(strategyColor)
                Text(engine.activeStrategy.label.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .heavy))
                    .foregroundStyle(strategyColor)
            }

            Spacer()

            HStack(spacing: 4) {
                if engine.isAdjusting {
                    Circle()
                        .fill(strategyColor)
                        .frame(width: 6, height: 6)
                        .symbolEffect(.pulse, options: .repeating)
                }
                Text("\(engine.livePairCount)")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(strategyColor)
                    .contentTransition(.numericText())
                Text("pr")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("\(engine.maxCap)")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var reasoningLine: some View {
        HStack(spacing: 6) {
            Image(systemName: engine.isAdjusting ? "sparkle" : "text.bubble")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(engine.currentReasoning)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sparklineGraph: some View {
        GeometryReader { geo in
            let points = engine.concurrencyHistory.suffix(60)
            let maxVal = max(engine.maxCap, 2)
            let width = geo.size.width
            let height = geo.size.height

            if points.count >= 2 {
                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                        let y = height - (height * CGFloat(point.concurrency) / CGFloat(maxVal))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(sparklineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                        let y = height - (height * CGFloat(point.concurrency) / CGFloat(maxVal))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    if let lastIndex = points.indices.last {
                        let lastX = width * CGFloat(lastIndex) / CGFloat(max(1, points.count - 1))
                        path.addLine(to: CGPoint(x: lastX, y: height))
                        path.addLine(to: CGPoint(x: 0, y: height))
                        path.closeSubpath()
                    }
                }
                .fill(sparklineColor.opacity(0.1))
            } else {
                Rectangle()
                    .fill(Color(.quaternarySystemFill))
                    .overlay {
                        Text("Collecting data...")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
            }
        }
        .frame(height: 40)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var sparklineColor: Color {
        guard engine.concurrencyHistory.count >= 2 else { return strategyColor }
        let last = engine.concurrencyHistory.last?.concurrency ?? 1
        let prev = engine.concurrencyHistory.dropLast().last?.concurrency ?? 1
        if last > prev { return .green }
        if last < prev { return .red }
        return .orange
    }

    private var factorBadges: some View {
        HStack(spacing: 6) {
            FactorBadge(
                icon: "memorychip",
                label: "\(engine.factorScores.memoryMB)MB",
                level: engine.factorScores.memory
            )
            FactorBadge(
                icon: "network",
                label: "\(engine.factorScores.networkLatencyMs)ms",
                level: engine.factorScores.network
            )
            FactorBadge(
                icon: "checkmark.circle",
                label: "\(Int(engine.factorScores.successRate * 100))%",
                level: engine.factorScores.successLevel
            )
            FactorBadge(
                icon: "bolt.shield",
                label: "\(Int(engine.factorScores.stability * 100))%",
                level: engine.factorScores.stabilityLevel
            )
            if engine.factorScores.isBackground {
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 8))
                    Text("BG")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

struct FactorBadge: View {
    let icon: String
    let label: String
    let level: ConcurrencyFactorLevel

    private var color: Color {
        switch level {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct ConcurrencyHistorySheet: View {
    let engine: AdaptiveConcurrencyEngine

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("\(engine.livePairCount)")
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .foregroundStyle(engine.activeStrategy.tintColor)
                            Text("Pairs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text("\(engine.maxCap)")
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("Max Cap")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            factorRow("Memory", level: engine.factorScores.memory, detail: "\(engine.factorScores.memoryMB)MB")
                            factorRow("Network", level: engine.factorScores.network, detail: "\(engine.factorScores.networkLatencyMs)ms")
                            factorRow("Success", level: engine.factorScores.successLevel, detail: "\(Int(engine.factorScores.successRate * 100))%")
                            factorRow("Stability", level: engine.factorScores.stabilityLevel, detail: "\(Int(engine.factorScores.stability * 100))%")
                        }
                    }
                } header: {
                    HStack {
                        Text("Current Status")
                        Spacer()
                        Label(engine.activeStrategy.label, systemImage: engine.activeStrategy.icon)
                            .font(.caption2.bold())
                            .foregroundStyle(engine.activeStrategy.tintColor)
                    }
                }

                Section {
                    if engine.decisions.isEmpty {
                        Text("No decisions yet — engine is warming up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.decisions) { decision in
                            decisionRow(decision)
                        }
                    }
                } header: {
                    Text("Decisions (\(engine.decisions.count))")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Concurrency History")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func factorRow(_ label: String, level: ConcurrencyFactorLevel, detail: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Circle()
                .fill(colorFor(level))
                .frame(width: 6, height: 6)
            Text(detail)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(colorFor(level))
        }
    }

    private func decisionRow(_ decision: ConcurrencyDecision) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(directionColor(decision.direction))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(decision.fromConcurrency) → \(decision.toConcurrency) pairs")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(directionColor(decision.direction))

                    if decision.wasAI {
                        Text("AI")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(decision.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(decision.reasoning)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text("mem \(decision.memoryMB)MB")
                    Text("success \(Int(decision.successRate * 100))%")
                    Text("stability \(Int(decision.stability * 100))%")
                    if decision.isBackground { Text("BG") }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 2)
    }

    private func directionColor(_ direction: ConcurrencyDecision.ConcurrencyDirection) -> Color {
        switch direction {
        case .rampUp: .green
        case .rampDown: .red
        case .hold: .orange
        }
    }

    private func colorFor(_ level: ConcurrencyFactorLevel) -> Color {
        switch level {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
