import SwiftUI

struct MainMenuView: View {
    @Binding var activeMode: ActiveAppMode?
    let requiresProfileSelection: Bool
    @State private var animateIn: Bool = false
    @State private var nordService = NordVPNService.shared
    private let proxyService = ProxyRotationService.shared

    private let twoColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    init(activeMode: Binding<ActiveAppMode?>, requiresProfileSelection: Bool = false) {
        _activeMode = activeMode
        self.requiresProfileSelection = requiresProfileSelection
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("MainMenuBG")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Color.black.opacity(0.3)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: geo.safeAreaInsets.top + 8)

                        profileSwitcher
                            .padding(.horizontal, dynamicIslandHPadding(geo: geo))
                            .padding(.bottom, 12)

                        if profileSelectionNeeded {
                            profileSelectionBanner
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }

                        // --- Core Modes ---
                        sectionHeader(title: "CORE MODES", icon: "star.fill")
                        LazyVGrid(columns: twoColumns, spacing: 8) {
                            slimButton(
                                title: "Unified Sessions",
                                subtitle: "Paired testing",
                                icon: "rectangle.split.2x1.fill",
                                color: .green,
                                mode: .unifiedSession
                            )
                            slimButton(
                                title: "Dual Find",
                                subtitle: "Email × 3 passwords",
                                icon: "magnifyingglass",
                                color: .purple,
                                mode: .dualFind
                            )
                            slimButton(
                                title: "Test & Debug",
                                subtitle: "Known account optimizer",
                                icon: "flask.fill",
                                color: .pink,
                                mode: .testDebug
                            )
                            slimButton(
                                title: "PPSR Check",
                                subtitle: "VIN & card testing",
                                icon: "car.side.fill",
                                color: .cyan,
                                mode: .ppsr
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                        // --- Tools & Monitoring ---
                        sectionHeader(title: "TOOLS & MONITORING", icon: "gauge.with.dots.needle.67percent")
                        LazyVGrid(columns: twoColumns, spacing: 8) {
                            slimButton(
                                title: "Super Test",
                                subtitle: "Full stack audit",
                                icon: "bolt.shield.fill",
                                color: .orange,
                                mode: .superTest
                            )
                            slimButton(
                                title: "Live Dashboard",
                                subtitle: "40-pair telemetry",
                                icon: "gauge.with.dots.needle.67percent",
                                color: .teal,
                                mode: .liveBatchDashboard
                            )
                            slimButton(
                                title: "Session Monitor",
                                subtitle: "Screenshots + logs",
                                icon: "rectangle.split.2x1",
                                color: .indigo,
                                mode: .sessionMonitor
                            )
                            slimButton(
                                title: "IP Score Test",
                                subtitle: "20× concurrent",
                                icon: "network.badge.shield.half.filled",
                                color: .blue,
                                mode: .ipScoreTest
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                        // --- Config & Utilities ---
                        sectionHeader(title: "CONFIG & UTILITIES", icon: "gearshape.2.fill")
                        LazyVGrid(columns: twoColumns, spacing: 8) {
                            slimButton(
                                title: "Settings & Testing",
                                subtitle: "Aggregated settings",
                                icon: "gearshape.2.fill",
                                color: Color(red: 0.4, green: 0.5, blue: 0.9),
                                mode: .settingsAndTesting
                            )
                            slimButton(
                                title: "Proxy Manager",
                                subtitle: "Pools & health",
                                icon: "arrow.triangle.2.circlepath",
                                color: .blue,
                                mode: .proxyManager
                            )
                            slimButton(
                                title: "Nord Config",
                                subtitle: "WireGuard / OVPN",
                                icon: "shield.checkered",
                                color: Color(red: 0.0, green: 0.78, blue: 1.0),
                                mode: .nordConfig
                            )
                            slimButton(
                                title: "Debug Log",
                                subtitle: "Live console",
                                icon: "doc.text.magnifyingglass",
                                color: .pink,
                                mode: .debugLog
                            )
                            slimButton(
                                title: "Flow Recorder",
                                subtitle: "Record & replay",
                                icon: "record.circle",
                                color: .red,
                                mode: .flowRecorder
                            )
                            slimButton(
                                title: "Vault",
                                subtitle: "Persistent files",
                                icon: "externaldrive.fill",
                                color: .mint,
                                mode: .vault
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                        // --- Connection Mode ---
                        connectionModeRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        // Version
                        HStack {
                            Spacer()
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.15))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 8)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.12)) {
                animateIn = true
            }
        }
        .onDisappear {
            animateIn = false
        }
    }

    // MARK: - Slim Button

    private func slimButton(title: String, subtitle: String, icon: String, color: Color, mode: ActiveAppMode) -> some View {
        Button {
            guard canEnterModes else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                activeMode = mode
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(animateIn ? (canEnterModes ? 1 : 0.35) : 0)
        .allowsHitTesting(canEnterModes)
        .sensoryFeedback(.selection, trigger: activeMode == mode)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .opacity(animateIn ? 1 : 0)
    }

    // MARK: - Connection Mode

    private var connectionModeRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(connectionModeColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: proxyService.unifiedConnectionMode.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(connectionModeColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CONNECTION MODE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text(proxyService.unifiedConnectionMode.label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Menu {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    Button {
                        proxyService.setUnifiedConnectionMode(mode)
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(proxyService.unifiedConnectionMode.label.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(connectionModeColor.opacity(0.45))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(connectionModeColor.opacity(0.12), lineWidth: 1)
        )
        .opacity(animateIn ? 1 : 0)
        .sensoryFeedback(.impact(weight: .medium), trigger: proxyService.unifiedConnectionMode)
    }

    // MARK: - Helpers

    private var connectionModeColor: Color {
        switch proxyService.unifiedConnectionMode {
        case .direct: .green
        case .proxy: .blue
        case .openvpn: .indigo
        case .wireguard: .purple
        case .dns: .cyan
        case .nodeMaven: .teal
        case .hybrid: .mint
        }
    }

    private func dynamicIslandHPadding(geo: GeometryProxy) -> CGFloat {
        let hasDynamicIsland = geo.safeAreaInsets.top > 51
        return hasDynamicIsland ? 56 : 20
    }

    private var profileSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(NordKeyProfile.allCases, id: \.self) { profile in
                Button {
                    guard !isProfileActive(profile) else { return }
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        nordService.switchProfile(profile)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(profile.rawValue.uppercased())
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(isProfileActive(profile) ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        Group {
                            if isProfileActive(profile) {
                                Capsule()
                                    .fill(
                                        profile == .nick
                                            ? LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                                    )
                            }
                        }
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .contentShape(Capsule())
        .sensoryFeedback(.impact(weight: .heavy), trigger: nordService.activeKeyProfile)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -20)
    }

    private var canEnterModes: Bool {
        !requiresProfileSelection || nordService.hasSelectedProfile
    }

    private var profileSelectionNeeded: Bool {
        requiresProfileSelection && !nordService.hasSelectedProfile
    }

    private func isProfileActive(_ profile: NordKeyProfile) -> Bool {
        nordService.hasSelectedProfile && nordService.activeKeyProfile == profile
    }

    private var profileSelectionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Nick or Poli to continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("No profile is selected automatically on first launch.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.10))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

nonisolated enum ActiveAppMode: String, Sendable {
    case unifiedSession
    case ppsr
    case superTest
    case debugLog
    case flowRecorder
    case nordConfig
    case vault
    case ipScoreTest
    case dualFind
    case settingsAndTesting
    case proxyManager
    case testDebug
    case liveBatchDashboard
    case sessionMonitor
}
