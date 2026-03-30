import SwiftUI

// MARK: - Keyboard Shortcuts Manager

@MainActor
final class KeyboardShortcutsManager {
    nonisolated(unsafe) static let shared = KeyboardShortcutsManager()

    private let logger = DebugLogger.shared

    enum ShortcutAction: String {
        case run = "Run Batch"
        case stop = "Stop Batch"
        case pause = "Pause Batch"
        case switchToLogin = "Switch to Login"
        case switchToPPSR = "Switch to PPSR"
        case switchToUnified = "Switch to Unified"
        case switchToDualFind = "Switch to DualFind"
        case switchToSuperTest = "Switch to SuperTest"
        case switchToSettings = "Switch to Settings"
        case search = "Search"
        case import = "Import"
        case export = "Export"
        case quickLook = "Quick Look"
    }

    private init() {
        logger.log("KeyboardShortcutsManager: initialized", category: .automation, level: .info)
    }

    func handleShortcut(_ action: ShortcutAction) {
        logger.log("KeyboardShortcutsManager: \(action.rawValue)", category: .automation, level: .info)

        switch action {
        case .run:
            // Trigger run based on active module
            break
        case .stop:
            // Stop active batch
            stopActiveBatch()
        case .pause:
            // Pause active batch
            pauseActiveBatch()
        case .switchToLogin, .switchToPPSR, .switchToUnified, .switchToDualFind, .switchToSuperTest, .switchToSettings:
            // Module switching handled by navigation
            break
        case .search, .import, .export, .quickLook:
            // Context-specific actions
            break
        }
    }

    private func stopActiveBatch() {
        if LoginViewModel.shared.isRunning {
            Task { await LoginViewModel.shared.stopBatch() }
        } else if PPSRAutomationViewModel.shared.isRunning {
            Task { await PPSRAutomationViewModel.shared.stopBatch() }
        } else if UnifiedSessionViewModel.shared.isRunning {
            Task { await UnifiedSessionViewModel.shared.stopBatch() }
        }
    }

    private func pauseActiveBatch() {
        BatchStateManager.shared.pauseBatch()
    }
}

// MARK: - Keyboard Shortcuts Extension

extension View {
    func sitchomaticKeyboardShortcuts() -> some View {
        self
            .keyboardShortcut("r", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.run)
            }
            .keyboardShortcut(".", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.stop)
            }
            .keyboardShortcut("p", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.pause)
            }
            .keyboardShortcut("1", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToLogin)
            }
            .keyboardShortcut("2", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToPPSR)
            }
            .keyboardShortcut("3", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToUnified)
            }
            .keyboardShortcut("4", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToDualFind)
            }
            .keyboardShortcut("5", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToSuperTest)
            }
            .keyboardShortcut("6", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.switchToSettings)
            }
            .keyboardShortcut("f", modifiers: .command) {
                KeyboardShortcutsManager.shared.handleShortcut(.search)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift]) {
                KeyboardShortcutsManager.shared.handleShortcut(.import)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift]) {
                KeyboardShortcutsManager.shared.handleShortcut(.export)
            }
            .keyboardShortcut(.space) {
                KeyboardShortcutsManager.shared.handleShortcut(.quickLook)
            }
    }
}

// MARK: - Pointer Interaction Support

struct HoverableListRow<Content: View>: View {
    let content: Content
    @State private var isHovered = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Context Menu Support

extension View {
    func credentialContextMenu(
        onRun: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) -> some View {
        self.contextMenu {
            Button(action: onRun) {
                Label("Run Test", systemImage: "play.fill")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Drag-to-Reorder Support

struct DraggableCredentialRow: View {
    let credential: LoginCredential
    let index: Int
    let onMove: (Int, Int) -> Void

    @State private var isDragging = false

    var body: some View {
        HoverableListRow {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(credential.username)
                        .font(.headline)

                    Text(credential.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("#\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .opacity(isDragging ? 0.5 : 1.0)
    }
}

// MARK: - Keyboard Shortcuts Help View

struct KeyboardShortcutsHelpView: View {
    let shortcuts: [(String, String, String)] = [
        ("⌘R", "Run", "Start batch automation"),
        ("⌘.", "Stop", "Stop current batch"),
        ("⌘P", "Pause", "Pause/resume batch"),
        ("⌘1", "Login", "Switch to Login module"),
        ("⌘2", "PPSR", "Switch to PPSR module"),
        ("⌘3", "Unified", "Switch to Unified module"),
        ("⌘4", "DualFind", "Switch to DualFind module"),
        ("⌘5", "SuperTest", "Switch to SuperTest module"),
        ("⌘6", "Settings", "Switch to Settings module"),
        ("⌘F", "Search", "Focus search field"),
        ("⌘⇧I", "Import", "Import credentials"),
        ("⌘⇧E", "Export", "Export results"),
        ("Space", "Quick Look", "Preview selected item"),
    ]

    var body: some View {
        List {
            Section("Keyboard Shortcuts") {
                ForEach(shortcuts, id: \.0) { shortcut in
                    HStack(spacing: 16) {
                        Text(shortcut.0)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 80, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.1)
                                .font(.headline)
                            Text(shortcut.2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Pointer Interactions") {
                VStack(alignment: .leading, spacing: 12) {
                    PointerTip(
                        icon: "hand.point.up.left.fill",
                        title: "Hover Effects",
                        description: "Hover over list rows to highlight them"
                    )

                    PointerTip(
                        icon: "contextualmenu.and.cursorarrow",
                        title: "Right-Click Menus",
                        description: "Right-click items for quick actions"
                    )

                    PointerTip(
                        icon: "arrow.up.and.down",
                        title: "Drag to Reorder",
                        description: "Drag credential rows to reorder the queue"
                    )
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Shortcuts & Gestures")
    }
}

struct PointerTip: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
