import SwiftUI

// MARK: - Module Definition

enum SitchomaticModule: String, CaseIterable, Identifiable, Sendable {
    case login = "Login"
    case ppsr = "PPSR"
    case unified = "Unified"
    case dualFind = "DualFind"
    case superTest = "SuperTest"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .login: return "person.circle.fill"
        case .ppsr: return "car.fill"
        case .unified: return "arrow.triangle.merge"
        case .dualFind: return "magnifyingglass.circle.fill"
        case .superTest: return "flame.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .login: return .blue
        case .ppsr: return .green
        case .unified: return .purple
        case .dualFind: return .orange
        case .superTest: return .red
        case .settings: return .gray
        }
    }
}

// MARK: - iPad Pro Root Navigation

struct iPadProRootNavigationView: View {
    @State private var selectedModule: SitchomaticModule? = .login
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Status tracking
    @State private var loginVM = LoginViewModel.shared
    @State private var ppsrVM = PPSRAutomationViewModel.shared
    @State private var unifiedVM = UnifiedSessionViewModel.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Module Selector
            ModuleSidebarView(selectedModule: $selectedModule)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
        } content: {
            // Content: Module-specific lists
            ModuleContentView(module: selectedModule)
                .navigationSplitViewColumnWidth(min: 350, ideal: 400, max: 500)
        } detail: {
            // Detail: Full context view
            ModuleDetailView(module: selectedModule)
                .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Module Sidebar

struct ModuleSidebarView: View {
    @Binding var selectedModule: SitchomaticModule?

    @State private var loginVM = LoginViewModel.shared
    @State private var ppsrVM = PPSRAutomationViewModel.shared
    @State private var unifiedVM = UnifiedSessionViewModel.shared

    var body: some View {
        List(SitchomaticModule.allCases, selection: $selectedModule) { module in
            NavigationLink(value: module) {
                HStack(spacing: 12) {
                    Image(systemName: module.icon)
                        .font(.title3)
                        .foregroundStyle(module.color)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.rawValue)
                            .font(.headline)

                        if let status = moduleStatus(for: module) {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let badge = moduleBadge(for: module) {
                        badge
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Sitchomatic")
        .listStyle(.sidebar)
    }

    private func moduleStatus(for module: SitchomaticModule) -> String? {
        switch module {
        case .login:
            if loginVM.isRunning {
                return "Running"
            } else if !loginVM.credentials.isEmpty {
                return "\(loginVM.credentials.count) credentials"
            }
        case .ppsr:
            if ppsrVM.isRunning {
                return "Running"
            } else if !ppsrVM.cards.isEmpty {
                return "\(ppsrVM.cards.count) cards"
            }
        case .unified:
            if unifiedVM.isRunning {
                return "Running"
            }
        default:
            break
        }
        return nil
    }

    @ViewBuilder
    private func moduleBadge(for module: SitchomaticModule) -> some View {
        switch module {
        case .login where loginVM.isRunning:
            LiveBadge(color: .blue)
        case .ppsr where ppsrVM.isRunning:
            LiveBadge(color: .green)
        case .unified where unifiedVM.isRunning:
            LiveBadge(color: .purple)
        default:
            EmptyView()
        }
    }
}

// MARK: - Module Content View

struct ModuleContentView: View {
    let module: SitchomaticModule?

    var body: some View {
        Group {
            if let module {
                moduleContentView(for: module)
            } else {
                Text("Select a module")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(module?.rawValue ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                moduleToolbar(for: module)
            }
        }
    }

    @ViewBuilder
    private func moduleContentView(for module: SitchomaticModule) -> some View {
        switch module {
        case .login:
            LoginCredentialsListView()
        case .ppsr:
            PPSRCardsListView()
        case .unified:
            UnifiedSessionFeedView()
        case .dualFind:
            DualFindListView()
        case .superTest:
            SuperTestListView()
        case .settings:
            SettingsListView()
        }
    }

    @ViewBuilder
    private func moduleToolbar(for module: SitchomaticModule?) -> some View {
        if let module {
            switch module {
            case .login, .ppsr, .unified:
                Button(action: {}) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Button(action: {}) {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button(action: {}) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            case .settings:
                Button(action: {}) {
                    Label("Export Settings", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Module Detail View

struct ModuleDetailView: View {
    let module: SitchomaticModule?

    var body: some View {
        Group {
            if let module {
                moduleDetailView(for: module)
            } else {
                Text("Select an item to view details")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func moduleDetailView(for module: SitchomaticModule) -> some View {
        switch module {
        case .login:
            LoginCredentialDetailView()
        case .ppsr:
            PPSRCardDetailView()
        case .unified:
            UnifiedSessionDetailView()
        case .dualFind:
            DualFindDetailView()
        case .superTest:
            SuperTestDetailView()
        case .settings:
            SettingsDetailView()
        }
    }
}

// MARK: - Live Badge

struct LiveBadge: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.2))
            .frame(width: 60, height: 24)
            .overlay(
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            )
    }
}

// MARK: - Placeholder List Views

struct PPSRCardsListView: View {
    var body: some View {
        Text("PPSR Cards List")
    }
}

struct DualFindListView: View {
    var body: some View {
        Text("DualFind List")
    }
}

struct SuperTestListView: View {
    var body: some View {
        Text("SuperTest List")
    }
}

struct SettingsListView: View {
    var body: some View {
        List {
            Section("General") {
                NavigationLink("Automation") {
                    Text("Automation Settings")
                }
                NavigationLink("Network") {
                    Text("Network Settings")
                }
                NavigationLink("Proxy") {
                    Text("Proxy Settings")
                }
            }
            Section("Advanced") {
                NavigationLink("Debug") {
                    Text("Debug Settings")
                }
                NavigationLink("Storage") {
                    Text("Storage Settings")
                }
            }
        }
    }
}

// MARK: - Placeholder Detail Views

struct UnifiedSessionDetailView: View {
    var body: some View {
        Text("Unified Session Detail")
    }
}

struct DualFindDetailView: View {
    var body: some View {
        Text("DualFind Detail")
    }
}

struct SuperTestDetailView: View {
    var body: some View {
        Text("SuperTest Detail")
    }
}

struct SettingsDetailView: View {
    var body: some View {
        Text("Settings Detail")
    }
}
