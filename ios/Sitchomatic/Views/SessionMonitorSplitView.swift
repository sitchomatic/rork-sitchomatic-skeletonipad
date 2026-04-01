import Foundation
import SwiftUI

// MARK: - Session Monitor Split View

struct SessionMonitorSplitView: View {
    @State private var unifiedVM = UnifiedSessionViewModel.shared
    @State private var screenshotManager = UnifiedScreenshotManager.shared
    @State private var logger = DebugLogger.shared

    @State private var selectedSessionId: String?
    @State private var refreshTick: Int = 0
    @State private var filterOption: SessionFilterOption = .all

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    nonisolated enum SessionFilterOption: String, CaseIterable, Sendable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case success = "Success"
        case failed = "Failed"
    }

    private var filteredSessions: [DualSiteSession] {
        switch filterOption {
        case .all: unifiedVM.sessions
        case .active: unifiedVM.sessions.filter { $0.globalState == .active }
        case .completed: unifiedVM.sessions.filter { $0.isTerminal }
        case .success: unifiedVM.sessions.filter { $0.globalState == .success }
        case .failed: unifiedVM.sessions.filter { $0.globalState == .abortPerm || $0.globalState == .abortTemp || $0.globalState == .exhausted }
        }
    }

    private var selectedSession: DualSiteSession? {
        guard let id = selectedSessionId else { return nil }
        return unifiedVM.sessions.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            sessionList
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            if let session = selectedSession {
                sessionDetail(session)
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Choose a session from the list to view its live screenshot and log stream.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
        }
    }

    // MARK: - Session List (Sidebar)

    private var sessionList: some View {
        VStack(spacing: 0) {
            filterBar
            sessionListContent
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionFilterOption.allCases, id: \.rawValue) { option in
                    Button {
                        withAnimation(.snappy) { filterOption = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filterOption == option ? Color.teal.opacity(0.15) : Color(.tertiarySystemFill))
                            .foregroundStyle(filterOption == option ? .teal : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var sessionListContent: some View {
        List(filteredSessions, id: \.id, selection: $selectedSessionId) { session in
            sessionRow(session)
                .tag(session.id)
        }
        .listStyle(.insetGrouped)
    }

    private func sessionRow(_ session: DualSiteSession) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(sessionStatusColor(session))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.credential.email)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(session.pairedBadgeText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(sessionStatusColor(session))

                    Text(session.formattedDuration)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Screenshot count badge
            let screenshotCount = screenshotManager.screenshotsForSession(session.id).count
            if screenshotCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 8))
                    Text("\(screenshotCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            selectedSessionId == session.id
                ? Color.teal.opacity(0.1)
                : Color(.secondarySystemGroupedBackground)
        )
    }

    // MARK: - Session Detail (Main Content)

    private func sessionDetail(_ session: DualSiteSession) -> some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 600

            if isWide {
                // Side-by-side on iPad landscape
                HStack(spacing: 0) {
                    screenshotPanel(session)
                        .frame(width: geo.size.width * 0.5)
                    Divider()
                    logStreamPanel(session)
                        .frame(width: geo.size.width * 0.5)
                }
            } else {
                // Stacked on narrow screens
                VStack(spacing: 0) {
                    screenshotPanel(session)
                        .frame(height: geo.size.height * 0.45)
                    Divider()
                    logStreamPanel(session)
                }
            }
        }
        .navigationTitle(session.credential.email)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sessionStatusBadge(session)
            }
        }
    }

    // MARK: - Screenshot Panel

    private func screenshotPanel(_ session: DualSiteSession) -> some View {
        let screenshots = screenshotManager.screenshotsForSession(session.id)

        return VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "camera.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
                Text("SCREENSHOTS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.teal)
                Spacer()
                Text("\(screenshots.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))

            if screenshots.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Screenshots Yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if session.globalState == .active {
                        Text("Screenshots will appear as the session progresses")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                screenshotGallery(screenshots)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func screenshotGallery(_ screenshots: [CapturedScreenshot]) -> some View {
        TabView {
            ForEach(screenshots) { screenshot in
                VStack(spacing: 6) {
                    Image(uiImage: screenshot.displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    HStack(spacing: 8) {
                        // Site label
                        Text(screenshot.site.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(screenshot.site == "joe" ? .green : .orange)

                        // Step label
                        Text(screenshot.step.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Detected outcome badge
                        if screenshot.detectedOutcome != .unknown {
                            Text(screenshot.detectedOutcome.rawValue)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(outcomeColor(screenshot.detectedOutcome))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(outcomeColor(screenshot.detectedOutcome).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(12)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    // MARK: - Log Stream Panel

    private func logStreamPanel(_ session: DualSiteSession) -> some View {
        let sessionLogs = logger.entries
            .filter { $0.sessionId == session.id }
            .suffix(50)

        return VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Text("LOG STREAM")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(sessionLogs.count) entries")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))

            if sessionLogs.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Logs Yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if session.globalState == .active {
                        Text("Logs will stream in real-time as the session runs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(sessionLogs, id: \.id) { entry in
                                logEntryRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: refreshTick) { _, _ in
                        if let lastId = sessionLogs.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func logEntryRow(_ entry: DebugLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.formattedTime)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            Text(entry.level.emoji)
                .font(.system(size: 9))
                .frame(width: 14)

            Text(entry.message)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(logLevelColor(entry.level))
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func sessionStatusColor(_ session: DualSiteSession) -> Color {
        switch session.globalState {
        case .active: .teal
        case .success: .green
        case .abortPerm: .red
        case .abortTemp: .orange
        case .exhausted: .secondary
        }
    }

    private func sessionStatusBadge(_ session: DualSiteSession) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sessionStatusColor(session))
                .frame(width: 6, height: 6)
            Text(session.pairedBadgeText)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(sessionStatusColor(session))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(sessionStatusColor(session).opacity(0.12))
        .clipShape(Capsule())
    }

    private func outcomeColor(_ outcome: VisionTextCropService.DetectedOutcome) -> Color {
        switch outcome {
        case .success: .green
        case .permDisabled: .red
        case .tempDisabled: .orange
        case .noAccount, .incorrectPassword: .secondary
        case .smsVerification: .yellow
        case .errorBanner: .red
        case .unknown: .tertiary
        }
    }

    private func logLevelColor(_ level: DebugLogLevel) -> Color {
        switch level {
        case .trace: .secondary
        case .debug: .secondary
        case .info: .primary
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .critical: .red
        }
    }
}
