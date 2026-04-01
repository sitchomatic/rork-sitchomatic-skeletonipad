import Foundation
import SwiftUI

// MARK: - Navigation Module

enum NavigationModule: String, CaseIterable, Identifiable, Sendable {
    case login, ppsr, unified, dualFind, superTest, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:     "Login Automation"
        case .ppsr:      "PPSR Gateway"
        case .unified:   "Unified Sessions"
        case .dualFind:  "Dual Find"
        case .superTest: "Super Test"
        case .settings:  "Settings & Testing"
        }
    }

    var subtitle: String {
        switch self {
        case .login:     "Credential batch testing"
        case .ppsr:      "Card registration checks"
        case .unified:   "Paired site sessions"
        case .dualFind:  "Dual-site discovery"
        case .superTest: "Comprehensive test suite"
        case .settings:  "Configuration & diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .login:     "person.badge.key.fill"
        case .ppsr:      "creditcard.fill"
        case .unified:   "point.3.connected.trianglepath.dotted"
        case .dualFind:  "magnifyingglass.circle.fill"
        case .superTest: "bolt.shield.fill"
        case .settings:  "gearshape.2.fill"
        }
    }

    var activeAppMode: ActiveAppMode {
        switch self {
        case .login:     .unifiedSession
        case .ppsr:      .ppsr
        case .unified:   .unifiedSession
        case .dualFind:  .dualFind
        case .superTest: .superTest
        case .settings:  .settingsAndTesting
        }
    }
}

// MARK: - iPad Navigation Shell

struct iPadNavigationShell: View {
    @State private var loginVM = LoginViewModel.shared
    @State private var ppsrVM = PPSRAutomationViewModel.shared
    @State private var unifiedVM = UnifiedSessionViewModel.shared
    @State private var batchState = BatchStateManager.shared

    @State private var selectedModule: NavigationModule? = .login
    @State private var selectedItemId: String?
    @State private var searchText: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .searchable(text: $searchText, prompt: searchPrompt)
        .withMainMenuButton()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationModule.allCases, selection: $selectedModule) { module in
            sidebarRow(for: module)
        }
        .listStyle(.sidebar)
        .navigationTitle("Sitchomatic")
        .onChange(of: selectedModule) { _, _ in
            selectedItemId = nil
        }
    }

    private func sidebarRow(for module: NavigationModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selectedModule == module ? .white : .white.opacity(0.7))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)

                Text(module.subtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            if isModuleRunning(module) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.6), radius: 4)
            }

            itemCountBadge(for: module)
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selectedModule)
    }

    @ViewBuilder
    private func itemCountBadge(for module: NavigationModule) -> some View {
        let count = itemCount(for: module)
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.15)))
        }
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        if let module = selectedModule {
            contentList(for: module)
                .navigationTitle(module.title)
        } else {
            ContentUnavailableView(
                "Select a Module",
                systemImage: "sidebar.squares.leading",
                description: Text("Choose a module from the sidebar.")
            )
        }
    }

    @ViewBuilder
    private func contentList(for module: NavigationModule) -> some View {
        switch module {
        case .login:
            loginContentList
        case .ppsr:
            ppsrContentList
        case .unified:
            unifiedContentList
        case .dualFind:
            dualFindContentList
        case .superTest:
            superTestContentList
        case .settings:
            settingsContentList
        }
    }

    private var loginContentList: some View {
        List(filteredCredentials, selection: $selectedItemId) { cred in
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cred.username)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(String(repeating: "•", count: min(cred.password.count, 12)))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                statusIndicator(for: cred.status)
            }
            .tag(cred.id)
        }
        .listStyle(.insetGrouped)
        .overlay { emptyOverlay(isEmpty: filteredCredentials.isEmpty, icon: "person.badge.key", label: "No Credentials") }
    }

    private var ppsrContentList: some View {
        List(filteredCards, selection: $selectedItemId) { card in
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.displayNumber)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(card.brand.rawValue)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
            }
            .tag(card.id)
        }
        .listStyle(.insetGrouped)
        .overlay { emptyOverlay(isEmpty: filteredCards.isEmpty, icon: "creditcard", label: "No Cards") }
    }

    private var unifiedContentList: some View {
        List(filteredSessions, selection: $selectedItemId) { session in
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.credential.email)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(session.globalState.rawValue)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            }
            .tag(session.id)
        }
        .listStyle(.insetGrouped)
        .overlay { emptyOverlay(isEmpty: filteredSessions.isEmpty, icon: "point.3.connected.trianglepath.dotted", label: "No Sessions") }
    }

    private var dualFindContentList: some View {
        placeholderContentList(icon: "magnifyingglass.circle", title: "Dual Find", subtitle: "Discovery results appear here")
    }

    private var superTestContentList: some View {
        placeholderContentList(icon: "bolt.shield", title: "Super Test", subtitle: "Test results appear here")
    }

    private var settingsContentList: some View {
        List {
            settingsRow(icon: "network", title: "Connection", tag: "conn")
            settingsRow(icon: "shield.checkered", title: "Stealth", tag: "stealth")
            settingsRow(icon: "gauge.with.dots.needle.33percent", title: "Performance", tag: "perf")
            settingsRow(icon: "ladybug.fill", title: "Debug", tag: "debug")
            settingsRow(icon: "clock.arrow.circlepath", title: "Auto-Retry", tag: "retry")
        }
        .listStyle(.insetGrouped)
    }

    private func settingsRow(icon: String, title: String, tag: String) -> some View {
        Button {
            selectedItemId = tag
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let itemId = selectedItemId, let module = selectedModule {
            detailView(for: module, itemId: itemId)
        } else {
            ContentUnavailableView(
                "Select an Item",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose an item from the list to view details.")
            )
        }
    }

    @ViewBuilder
    private func detailView(for module: NavigationModule, itemId: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(for: module, itemId: itemId)
                batchStatusCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailHeader(for module: NavigationModule, itemId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: module.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(module.title)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Text("Item: \(itemId)")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var batchStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BATCH STATUS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 20) {
                statPill(label: "Success", value: "\(batchState.successCount)", color: .green)
                statPill(label: "Fail", value: "\(batchState.failureCount)", color: .red)
                statPill(label: "Total", value: "\(batchState.totalCount)", color: .blue)
            }

            if batchState.isRunning {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.cyan)
                    Text("Batch running…")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Helpers

    private func isModuleRunning(_ module: NavigationModule) -> Bool {
        switch module {
        case .login:     loginVM.isRunning
        case .ppsr:      ppsrVM.isRunning
        case .unified:   unifiedVM.isRunning
        case .dualFind:  false
        case .superTest: false
        case .settings:  false
        }
    }

    private func itemCount(for module: NavigationModule) -> Int {
        switch module {
        case .login:     loginVM.credentials.count
        case .ppsr:      ppsrVM.cards.count
        case .unified:   unifiedVM.sessions.count
        case .dualFind:  0
        case .superTest: 0
        case .settings:  0
        }
    }

    @ViewBuilder
    private func statusIndicator(for status: CredentialStatus) -> some View {
        let (color, icon): (Color, String) = switch status {
        case .untested:      (.gray, "circle.dashed")
        case .testing:       (.yellow, "arrow.triangle.2.circlepath")
        case .working:       (.green, "checkmark.circle.fill")
        case .noAcc:         (.red, "xmark.circle.fill")
        case .permDisabled:  (.red, "lock.slash.fill")
        case .tempDisabled:  (.orange, "lock.fill")
        case .unsure:        (.yellow, "questionmark.circle.fill")
        }
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(color)
    }

    private func placeholderContentList(icon: String, title: String, subtitle: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(subtitle)
        )
    }

    @ViewBuilder
    private func emptyOverlay(isEmpty: Bool, icon: String, label: String) -> some View {
        if isEmpty {
            ContentUnavailableView(label, systemImage: icon)
        }
    }

    // MARK: - Filtered Data

    private var searchPrompt: String {
        switch selectedModule {
        case .login:     "Search credentials…"
        case .ppsr:      "Search cards…"
        case .unified:   "Search sessions…"
        case .dualFind:  "Search results…"
        case .superTest: "Search tests…"
        case .settings:  "Search settings…"
        case .none:      "Search…"
        }
    }

    private var filteredCredentials: [LoginCredential] {
        guard !searchText.isEmpty else { return loginVM.credentials }
        return loginVM.credentials.filter {
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredCards: [PPSRCard] {
        guard !searchText.isEmpty else { return ppsrVM.cards }
        return ppsrVM.cards.filter {
            $0.displayNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.brand.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSessions: [DualSiteSession] {
        guard !searchText.isEmpty else { return unifiedVM.sessions }
        return unifiedVM.sessions.filter {
            $0.credential.email.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Preview

#Preview {
    iPadNavigationShell()
}
