import SwiftUI

struct SettingsAndTestingView: View {
    private let proxyService = ProxyRotationService.shared

    var body: some View {
        NavigationStack {
            List {
                testingToolsSection
                networkAndVPNSection
                advancedSettingsLinkSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings & Testing")
        }
        .withMainMenuButton()
        .preferredColorScheme(.dark)
    }

    private var testingToolsSection: some View {
        Section {
            NavigationLink {
                LiveBatchDashboardView()
            } label: {
                settingsRow(
                    icon: "gauge.with.dots.needle.50percent",
                    title: "Live Batch Dashboard",
                    subtitle: "Real-time WebView, throughput & AI monitoring",
                    color: .teal
                )
            }

            NavigationLink {
                SessionMonitorSplitView()
            } label: {
                settingsRow(
                    icon: "rectangle.split.2x1",
                    title: "Session Monitor",
                    subtitle: "Live screenshot + log stream split view",
                    color: .purple
                )
            }

            NavigationLink {
                SuperTestView()
            } label: {
                settingsRow(
                    icon: "bolt.horizontal.circle.fill",
                    title: "Super Test",
                    subtitle: "Full infrastructure validation",
                    color: .purple
                )
            }

            NavigationLink {
                IPScoreTestView()
            } label: {
                settingsRow(
                    icon: "network.badge.shield.half.filled",
                    title: "IP Score Test",
                    subtitle: "20x concurrent IP quality analysis",
                    color: .indigo
                )
            }

            NavigationLink {
                BatchIntelligenceView()
            } label: {
                settingsRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Batch Intelligence",
                    subtitle: "AI pre-optimizer, credential triage & domain intel",
                    color: .blue
                )
            }

            NavigationLink {
                WebViewMemoryProfilerView()
            } label: {
                settingsRow(
                    icon: "chart.xyaxis.line",
                    title: "WebView Memory Profiler",
                    subtitle: "Per-webview memory & eviction recommendations",
                    color: .orange
                )
            }

            NavigationLink {
                BatchTelemetryDashboardView()
            } label: {
                settingsRow(
                    icon: "chart.bar.xaxis",
                    title: "Batch Telemetry",
                    subtitle: "Historical batch analytics & performance metrics",
                    color: .green
                )
            }

            NavigationLink {
                PerformanceMonitorView()
            } label: {
                settingsRow(
                    icon: "speedometer",
                    title: "Performance Monitor",
                    subtitle: "OS signpost, task tracking & memory instrumentation",
                    color: .red
                )
            }
        } header: {
            Label("Testing Tools", systemImage: "flask.fill")
        } footer: {
            Text("Run full infrastructure tests, IP quality checks, and performance analysis.")
        }
    }

    private var networkAndVPNSection: some View {
        Section {
            NavigationLink {
                DeviceNetworkSettingsView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device Network Settings").font(.subheadline.bold())
                        Text("Proxy, VPN, WireGuard, DNS — all modes")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(proxyService.unifiedConnectionMode.label)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12)).clipShape(Capsule())
                }
            }

            NavigationLink {
                NordLynxConfigView()
            } label: {
                settingsRow(
                    icon: "shield.checkered",
                    title: "Nord Config",
                    subtitle: "WireGuard & OpenVPN generation",
                    color: Color(red: 0.0, green: 0.78, blue: 1.0)
                )
            }

            NavigationLink {
                NetworkRepairView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.body)
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repair Network").font(.subheadline.bold())
                        Text("Full restart of all network protocols")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if NetworkRepairService.shared.isRepairing {
                        ProgressView()
                            .controlSize(.mini)
                    } else if let result = NetworkRepairService.shared.lastRepairResult {
                        Image(systemName: result.overallSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.overallSuccess ? .green : .red)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Label("Network & VPN", systemImage: "lock.shield.fill")
        } footer: {
            Text("Network configs are device-wide. Changes apply to Joe, Ignition & PPSR.")
        }
    }

    private var advancedSettingsLinkSection: some View {
        Section {
            NavigationLink {
                GrokAIStatusView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(GrokAISetup.isConfigured ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "brain.head.profile.fill")
                            .font(.body)
                            .foregroundStyle(GrokAISetup.isConfigured ? .green : .orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grok AI Status")
                            .font(.subheadline.bold())
                        Text(GrokAISetup.isConfigured ? "Connected — vision + reasoning active" : "Not configured — heuristic mode")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: GrokAISetup.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(GrokAISetup.isConfigured ? .green : .orange)
                        .font(.caption)
                }
            }

            NavigationLink {
                AdvancedSettingsView()
            } label: {
                settingsRow(
                    icon: "gearshape.2.fill",
                    title: "Advanced Settings",
                    subtitle: "Debug, diagnostics, data, app settings & about",
                    color: .gray
                )
            }
        } header: {
            Label("Advanced", systemImage: "ellipsis.circle.fill")
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsConsoleView: View {
    @State private var logs: [DebugLogEntry] = []

    var body: some View {
        List {
            if logs.isEmpty {
                Text("No log entries").foregroundStyle(.tertiary)
            } else {
                ForEach(logs) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.formattedTime)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .leading)
                        Text(entry.level.emoji)
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .frame(width: 20)
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Console")
        .onAppear {
            logs = Array(DebugLogger.shared.entries.suffix(100).reversed())
        }
        .refreshable {
            logs = Array(DebugLogger.shared.entries.suffix(100).reversed())
        }
    }
}
