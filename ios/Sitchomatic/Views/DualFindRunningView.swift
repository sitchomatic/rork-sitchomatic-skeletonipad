import SwiftUI

struct DualFindRunningView: View {
    @Bindable var vm: DualFindViewModel
    @State private var showShareSheet: Bool = false
    @State private var showLiveFeed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(spacing: 14) {
                    NetworkTruthCompactView()

                    liveFeedButton

                    hitsSection

                    sessionGrid

                    logFeed
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if vm.waitingForSetAdvance {
                setAdvanceBanner
            }

            controlBar
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $vm.showLoginFound) {
            loginFoundSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            let text = vm.exportAllHits()
            ShareSheetView(items: [text])
        }
        .sheet(isPresented: $showLiveFeed) {
            UnifiedScreenshotFeedView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $vm.showInterventionSheet) {
            interventionSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: vm.hits.count)
        .sensoryFeedback(.warning, trigger: vm.interventionUnsureCount)
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.progressText)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Text("\(vm.hits.count) hit\(vm.hits.count == 1 ? "" : "s") · \(vm.disabledEmails.count) disabled · \(vm.completedTests) tested")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))

                        if vm.passwordSets.count > 1 {
                            Text("· \(vm.completedSets)/\(vm.passwordSets.count) sets")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.purple.opacity(0.8))
                        }
                    }
                }

                Spacer()

                Text(vm.runStatusLabel)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(vm.runStatusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.runStatusColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            ProgressView(value: vm.progressFraction)
                .tint(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Hits

    @ViewBuilder
    private var hitsSection: some View {
        if !vm.hits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Hits Found", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)

                    Spacer()

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                }

                ForEach(vm.hits) { hit in
                    Button {
                        vm.copyHit(hit)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hit.platform.contains("Joe") ? "suit.spade.fill" : "flame.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(hit.platform.contains("Joe") ? .green : .orange)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.email)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Text(hit.password)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()

                            if vm.copiedHitId == hit.id {
                                Label("Copied", systemImage: "checkmark")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            } else {
                                Text(hit.platform.contains("Joe") ? "JOE" : "IGN")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(10)
                        .background(.green.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .sensoryFeedback(.selection, trigger: vm.copiedHitId)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
            .animation(.default, value: vm.copiedHitId)
        }
    }

    // MARK: - Session Grid

    private var sessionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sessions", systemImage: "rectangle.stack")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(vm.sessions, id: \.id) { session in
                    sessionCard(session)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func sessionCard(_ session: DualFindSessionInfo) -> some View {
        let isJoe = session.platform.contains("Joe")
        let accent: Color = isJoe ? .green : .orange
        let platformPaused = isJoe ? vm.isJoePaused : vm.isIgnPaused

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isJoe ? "suit.spade.fill" : "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accent)

                Text(isJoe ? "JOE" : "IGN")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)

                Text("#\(session.index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                if platformPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                } else {
                    Circle()
                        .fill(session.isActive ? .green : .gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            if !session.currentEmail.isEmpty {
                Text(session.currentEmail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(platformPaused ? "Paused" : session.status)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(platformPaused ? .yellow : statusColor(session.status))
        }
        .padding(10)
        .background(accent.opacity(0.06))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "HIT!": .green
        case "Disabled": .red
        case "Testing", "Rebuilding": .yellow
        case "No Acc", "Done": .white.opacity(0.3)
        case _ where status.contains("UNSURE"): .orange
        default: .white.opacity(0.4)
        }
    }

    // MARK: - Intervention Sheet

    private var interventionSheet: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UNSURE RESULT")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("Session frozen — your input needed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 8)

            if let req = vm.activeIntervention {
                VStack(spacing: 8) {
                    interventionInfoRow("Session", value: req.sessionLabel)
                    interventionInfoRow("Email", value: req.email)
                    interventionInfoRow("Password", value: req.password)
                    interventionInfoRow("Platform", value: req.platform)
                    interventionInfoRow("URL", value: URL(string: req.currentURL)?.host ?? req.currentURL)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))

                if !req.pageContent.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Page Content Preview")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(String(req.pageContent.prefix(500)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 100)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What is the correct result?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(DualFindInterventionAction.allCases) { action in
                        Button {
                            vm.interventionResponse = action
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 12))
                                Text(action.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(actionColor(action).opacity(0.7))
                            .clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }
            }

            if vm.interventionLearning.totalCorrections > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text("AI learned from \(vm.interventionLearning.totalCorrections) corrections · \(vm.interventionAutoHealCount) auto-healed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func actionColor(_ action: DualFindInterventionAction) -> Color {
        switch action {
        case .markSuccess: .green
        case .markNoAccount: .red
        case .markDisabled: .orange
        case .restartWithNewIP: .blue
        case .pressSubmitAgain: .purple
        case .disableURL: .pink
        case .disableViewport: .indigo
        case .skipAndContinue: .gray
        }
    }

    private func interventionInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    // MARK: - Set Advance Banner

    private var setAdvanceBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: vm.waitingForSetAdvance)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set \(vm.currentSetIndex + 1) Complete")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    let remaining = vm.passwordSets.count - vm.currentSetIndex - 1
                    Text("\(remaining) set\(remaining == 1 ? "" : "s") remaining in queue")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
            }

            Button {
                vm.advanceToNextSet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Start Set \(vm.currentSetIndex + 2)")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.purple)
                .clipShape(.rect(cornerRadius: 10))
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: vm.waitingForSetAdvance)
        }
        .padding(14)
        .background(.green.opacity(0.08))
    }

    // MARK: - Live Feed Button

    private var liveFeedButton: some View {
        Button {
            showLiveFeed = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, isActive: !vm.liveScreenshots.isEmpty)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Screenshot Feed")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(vm.liveScreenshots.count) screenshot\(vm.liveScreenshots.count == 1 ? "" : "s") captured · \(vm.screenshotCount.label)/attempt")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(12)
            .background(.cyan.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.cyan.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Log Feed

    private var logFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Log", systemImage: "text.alignleft")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(vm.logs.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(vm.logs.prefix(200)) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text(entry.formattedTime)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))

                        Text(entry.message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(logColor(entry.level))
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func logColor(_ level: PPSRLogEntry.Level) -> Color {
        switch level {
        case .info: .white.opacity(0.5)
        case .success: .green
        case .warning: .yellow
        case .error: .red
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            if vm.isJoePaused || vm.isIgnPaused {
                Button {
                    vm.resumeAll()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.green)
                        .clipShape(.rect(cornerRadius: 10))
                }
            } else {
                Button {
                    vm.pauseAll()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.yellow.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 10))
                }
            }

            Button {
                vm.stopRun()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.red.opacity(0.8))
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Login Found Sheet

    private var loginFoundSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: vm.latestHit?.id)

            Text("LOGIN FOUND")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(.green)

            if let hit = vm.latestHit {
                VStack(spacing: 8) {
                    HStack {
                        Text("Email")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(hit.email)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack {
                        Text("Password")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(hit.password)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack {
                        Text("Platform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(hit.platform)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(hit.platform.contains("Joe") ? .green : .orange)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))

                Button {
                    vm.copyHit(hit)
                } label: {
                    Label(vm.copiedHitId == hit.id ? "Copied!" : "Copy Credentials", systemImage: vm.copiedHitId == hit.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 10))
                }
                .sensoryFeedback(.selection, trigger: vm.copiedHitId)
            }

            Text("Only \(vm.latestHit?.platform.contains("Joe") == true ? "JoePoint" : "Ignition Lite") is paused. The other platform continues testing.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                vm.showLoginFound = false
                if vm.isJoePaused { vm.isJoePaused = false }
                if vm.isIgnPaused { vm.isIgnPaused = false }
            } label: {
                Text("Continue Testing")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.purple)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(24)
    }
}

