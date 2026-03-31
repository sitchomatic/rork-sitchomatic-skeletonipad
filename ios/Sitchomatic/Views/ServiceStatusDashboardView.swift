import SwiftUI

struct ServiceStatusDashboardView: View {
    @State private var refreshTick: Int = 0
    @State private var refreshTimer: Timer?

    private let batchState = BatchStateManager.shared
    private let crashProtection = CrashProtectionService.shared
    private let stability = AppStabilityCoordinator.shared
    private let recycler = WebViewRecycler.shared
    private let poolManager = WebViewProcessPoolManager.shared
    private let governor = ConcurrencyGovernorV2.shared
    private let proxyHealth = ProxyHealthMonitor.shared
    private let networkResilience = NetworkResilienceService.shared
    private let telemetry = BatchTelemetryService.shared
    private let onDeviceAI = OnDeviceAIService.shared

    var body: some View {
        List {
            // Force body re-evaluation on timer tick for live status updates
            let _ = refreshTick
            coreSystemsSection
            aiServicesSection
            networkSection
            webViewSection
            telemetrySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Service Status")
        .onAppear {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in refreshTick += 1 }
            }
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - Core Systems

    private var coreSystemsSection: some View {
        Section {
            statusRow(
                icon: "bolt.shield.fill",
                title: "Batch State Manager",
                status: batchState.isRunning ? (batchState.isPaused ? "PAUSED" : "RUNNING") : "IDLE",
                statusColor: batchState.isRunning ? (batchState.isPaused ? .orange : .green) : .secondary,
                detail: batchState.isRunning
                    ? "\(batchState.successCount)/\(batchState.totalCount) · \(String(format: "%.1f", batchState.throughputPerMinute))/min"
                    : "No active batch"
            )

            statusRow(
                icon: "shield.checkered",
                title: "Crash Protection",
                status: crashProtection.isMemoryEmergency ? "EMERGENCY" : (crashProtection.isMemoryCritical ? "CRITICAL" : "OK"),
                statusColor: crashProtection.isMemoryEmergency ? .red : (crashProtection.isMemoryCritical ? .orange : .green),
                detail: "Crashes: \(crashProtection.totalCrashCount) · Max: \(crashProtection.recommendedMaxConcurrency) pairs"
            )

            if let report = stability.lastHealthReport {
                statusRow(
                    icon: "heart.text.square.fill",
                    title: "App Stability",
                    status: report.overallHealthy ? "HEALTHY" : "UNHEALTHY",
                    statusColor: report.overallHealthy ? .green : .red,
                    detail: "Memory: \(report.memoryMB)MB · WebViews: \(report.webViewCount)"
                )
            } else {
                statusRow(
                    icon: "heart.text.square.fill",
                    title: "App Stability",
                    status: "INIT",
                    statusColor: .secondary,
                    detail: "Awaiting first health check"
                )
            }
        } header: {
            Label("Core Systems", systemImage: "cpu")
        }
    }

    // MARK: - AI Services

    private var aiServicesSection: some View {
        Section {
            let stats = AIAnalysisEngine.shared.getStats()
            statusRow(
                icon: "brain.head.profile.fill",
                title: "AI Analysis Engine",
                status: stats.processingRequests > 0 ? "ACTIVE" : "READY",
                statusColor: stats.processingRequests > 0 ? .blue : .green,
                detail: "Requests: \(stats.totalRequests) · Cache: \(stats.cacheHits)/\(stats.cacheHits + stats.cacheMisses) · Avg: \(stats.avgResponseTimeMs)ms"
            )

            statusRow(
                icon: "brain.fill",
                title: "On-Device AI",
                status: onDeviceAI.isAvailable ? "AVAILABLE" : "FALLBACK",
                statusColor: onDeviceAI.isAvailable ? .green : .orange,
                detail: "Grok: \(GrokAISetup.isConfigured ? "configured" : "not configured")"
            )
        } header: {
            Label("AI Services", systemImage: "brain")
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        Section {
            let proxyStats = ProxyOrchestrator.shared.getStats()
            statusRow(
                icon: "server.rack",
                title: "Proxy Orchestrator",
                status: proxyStats.healthy > 0 ? "ONLINE" : (proxyStats.total > 0 ? "DEGRADED" : "EMPTY"),
                statusColor: proxyStats.healthy > 0 ? .green : (proxyStats.total > 0 ? .orange : .secondary),
                detail: "Healthy: \(proxyStats.healthy)/\(proxyStats.total) · Latency: \(String(format: "%.0f", proxyStats.avgLatency))ms · Rate: \(String(format: "%.0f%%", proxyStats.successRate * 100))"
            )

            statusRow(
                icon: "waveform.path.ecg",
                title: "Proxy Health Monitor",
                status: proxyHealth.isMonitoring ? (proxyHealth.upstreamHealth.isHealthy ? "HEALTHY" : "UNHEALTHY") : "STOPPED",
                statusColor: proxyHealth.isMonitoring ? (proxyHealth.upstreamHealth.isHealthy ? .green : .red) : .secondary,
                detail: proxyHealth.isMonitoring
                    ? "Latency: \(proxyHealth.averageLatencyMs ?? 0)ms · Success: \(String(format: "%.0f%%", proxyHealth.successRate * 100))"
                    : "Not monitoring"
            )

            statusRow(
                icon: "network.badge.shield.half.filled",
                title: "Network Resilience",
                status: networkResilience.isThrottled ? "THROTTLED" : "NORMAL",
                statusColor: networkResilience.isThrottled ? .orange : .green,
                detail: "Bandwidth: \(formatBandwidth(networkResilience.bandwidthEstimateBps)) · Concurrency: \(networkResilience.currentConcurrencyLimit)"
            )
        } header: {
            Label("Network & Proxy", systemImage: "globe")
        }
    }

    // MARK: - WebView Infrastructure

    private var webViewSection: some View {
        Section {
            statusRow(
                icon: "arrow.triangle.2.circlepath",
                title: "WebView Recycler",
                status: "POOL: \(recycler.poolSize)",
                statusColor: .blue,
                detail: "Checkouts: \(recycler.totalCheckouts) · Returns: \(recycler.totalReturns) · Fresh: \(recycler.totalCreatedFresh)"
            )

            statusRow(
                icon: "square.stack.3d.up",
                title: "Process Pool Manager",
                status: "\(poolManager.poolCount) pool\(poolManager.poolCount == 1 ? "" : "s")",
                statusColor: .blue,
                detail: "Mode: \(processPoolModeLabel)"
            )

            let govStats = governor.getStats()
            statusRow(
                icon: "gauge.with.dots.needle.bottom.100percent",
                title: "Concurrency Governor",
                status: governor.isRampingUp ? "RAMP UP" : (governor.isRampingDown ? "RAMP DOWN" : "STABLE"),
                statusColor: governor.isRampingUp ? .green : (governor.isRampingDown ? .orange : .blue),
                detail: "Current: \(govStats.current)/\(govStats.target) pairs · Success: \(String(format: "%.0f%%", govStats.successRate * 100))"
            )
        } header: {
            Label("WebView Infrastructure", systemImage: "rectangle.on.rectangle")
        }
    }

    // MARK: - Telemetry

    private var telemetrySection: some View {
        Section {
            let records = telemetry.batchRecords
            statusRow(
                icon: "chart.bar.xaxis",
                title: "Batch Telemetry",
                status: "\(records.count) batch\(records.count == 1 ? "" : "es")",
                statusColor: .teal,
                detail: records.last.map { r in
                    "Last: \(r.successCount)/\(r.processedItems) · Avg: \(r.avgLatencyMs)ms"
                } ?? "No batch data"
            )
        } header: {
            Label("Telemetry & Persistence", systemImage: "chart.xyaxis.line")
        }
    }

    // MARK: - Helpers

    private func statusRow(icon: String, title: String, status: String, statusColor: Color, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(status)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func formatBandwidth(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f Kbps", bps / 1_000)
        } else if bps > 0 {
            return String(format: "%.0f bps", bps)
        }
        return "N/A"
    }

    private var processPoolModeLabel: String {
        switch poolManager.mode {
        case .single: "Single (shared)"
        case .tiered(let count): "Tiered (\(count) pools)"
        }
    }
}
