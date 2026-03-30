import SwiftUI

// MARK: - Keyboard Shortcut Modifier

struct KeyboardShortcutModifier: ViewModifier {
    @Binding var activeMode: ActiveAppMode?
    @Binding var isSearchFocused: Bool

    private var batch: BatchStateManager { BatchStateManager.shared }

    func body(content: Content) -> some View {
        content
            .background(
                batchShortcuts
                    .frame(width: 0, height: 0)
                    .hidden()
                    .accessibilityHidden(false)
            )
    }

    // SwiftUI only allows one .keyboardShortcut per view, so we
    // layer invisible buttons to register additional shortcuts.
    @ViewBuilder
    private var batchShortcuts: some View {
        // ⌘R – Run batch
        Button("Run Batch") { startBatchIfIdle() }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()

        // ⌘. – Stop batch
        Button("Stop Batch") { stopBatch() }
            .keyboardShortcut(".", modifiers: .command)
            .hidden()

        // ⌘P – Pause / Resume toggle
        Button("Pause or Resume Batch") { togglePauseResume() }
            .keyboardShortcut("p", modifiers: .command)
            .hidden()

        // ⌘1–⌘6 – Module switching
        Button("Unified Session") { activeMode = .unifiedSession }
            .keyboardShortcut("1", modifiers: .command)
            .hidden()

        Button("PPSR") { activeMode = .ppsr }
            .keyboardShortcut("2", modifiers: .command)
            .hidden()

        Button("Super Test") { activeMode = .superTest }
            .keyboardShortcut("3", modifiers: .command)
            .hidden()

        Button("Dual Find") { activeMode = .dualFind }
            .keyboardShortcut("4", modifiers: .command)
            .hidden()

        Button("Live Batch Dashboard") { activeMode = .liveBatchDashboard }
            .keyboardShortcut("5", modifiers: .command)
            .hidden()

        Button("Session Monitor") { activeMode = .sessionMonitor }
            .keyboardShortcut("6", modifiers: .command)
            .hidden()

        // ⌘F – Focus search
        Button("Focus Search") { isSearchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()

        // ⌘⇧I – Import
        Button("Import") { postNotification(.importRequested) }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .hidden()

        // ⌘⇧E – Export
        Button("Export") { postNotification(.exportRequested) }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .hidden()

        // Space – Quick look / preview
        Button("Quick Look") { postNotification(.quickLookRequested) }
            .keyboardShortcut(.space, modifiers: [])
            .hidden()

        // ⌘⇧D – Debug log
        Button("Debug Log") { activeMode = .debugLog }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .hidden()

        // ⌘, – Settings
        Button("Settings") { activeMode = .settingsAndTesting }
            .keyboardShortcut(",", modifiers: .command)
            .hidden()
    }

    // MARK: - Actions

    private func startBatchIfIdle() {
        guard !batch.isRunning else { return }
        batch.startBatch()
    }

    private func stopBatch() {
        guard batch.isRunning else { return }
        batch.stopBatch()
    }

    private func togglePauseResume() {
        guard batch.isRunning else { return }
        if batch.isPaused {
            batch.resumeBatch()
        } else {
            batch.pauseBatch()
        }
    }

    private func postNotification(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importRequested = Notification.Name("importRequested")
    static let exportRequested = Notification.Name("exportRequested")
    static let quickLookRequested = Notification.Name("quickLookRequested")
}

// MARK: - Hover Highlight Modifier

struct HoverHighlightModifier: ViewModifier {
    @State private var isHovered = false

    var highlightColor: Color = .white.opacity(0.06)
    var scaleEffect: CGFloat = 1.015

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? highlightColor : Color.clear)
            )
            .scaleEffect(isHovered ? scaleEffect : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Context Menu Modifier

struct ContextMenuModifier<MenuContent: View>: ViewModifier {
    let menuContent: () -> MenuContent

    func body(content: Content) -> some View {
        content
            .contextMenu { menuContent() }
    }
}

struct SingleActionContextMenuModifier: ViewModifier {
    let label: String
    let systemImage: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(action: action) {
                    Label(label, systemImage: systemImage)
                }
            }
    }
}

// MARK: - View Extensions

extension View {

    /// Attaches full keyboard‐shortcut overlay for iPad Pro.
    func withKeyboardShortcuts(
        activeMode: Binding<ActiveAppMode?>,
        isSearchFocused: Binding<Bool> = .constant(false)
    ) -> some View {
        modifier(
            KeyboardShortcutModifier(
                activeMode: activeMode,
                isSearchFocused: isSearchFocused
            )
        )
    }

    /// Adds a subtle highlight and scale effect on trackpad hover.
    func withHoverHighlight(
        color: Color = .white.opacity(0.06),
        scale: CGFloat = 1.015
    ) -> some View {
        modifier(
            HoverHighlightModifier(
                highlightColor: color,
                scaleEffect: scale
            )
        )
    }

    /// Attaches a single‐action right‐click context menu.
    func withItemContextMenu(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            SingleActionContextMenuModifier(
                label: label,
                systemImage: systemImage,
                action: action
            )
        )
    }

    /// Attaches a custom right‐click context menu built from the provided content.
    func withContextMenu<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(ContextMenuModifier(menuContent: content))
    }
}
