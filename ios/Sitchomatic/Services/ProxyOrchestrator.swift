import Foundation
import Observation

// MARK: - Network Failure

nonisolated enum NetworkFailure: Error, Sendable, LocalizedError {
    case connectionRefused
    case handshakeFailed
    case authenticationFailed
    case timeout
    case dnsResolutionFailed
    case tunnelEstablishmentFailed
    case proxyRotationExhausted
    case rateLimited
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .connectionRefused: "Connection refused by remote host"
        case .handshakeFailed: "TLS/SOCKS5 handshake failed"
        case .authenticationFailed: "Proxy authentication failed"
        case .timeout: "Connection timed out"
        case .dnsResolutionFailed: "DNS resolution failed"
        case .tunnelEstablishmentFailed: "Tunnel establishment failed"
        case .proxyRotationExhausted: "All proxy candidates exhausted"
        case .rateLimited: "Rate limited by upstream"
        case .unknown(let reason): "Unknown failure: \(reason)"
        }
    }
}

// MARK: - Proxy Protocol

nonisolated enum ProxyProtocol: String, CaseIterable, Sendable {
    case socks5 = "SOCKS5"
    case wireGuard = "WireGuard"
    case openVPN = "OpenVPN"
    case nodeMaven = "NodeMaven"
    case direct = "Direct"
    case dns = "DNS"
    case hybrid = "Hybrid"

    var icon: String {
        switch self {
        case .socks5: "network"
        case .wireGuard: "lock.trianglebadge.exclamationmark.fill"
        case .openVPN: "shield.lefthalf.filled"
        case .nodeMaven: "globe"
        case .direct: "bolt.horizontal.fill"
        case .dns: "lock.shield.fill"
        case .hybrid: "arrow.triangle.branch"
        }
    }

    var toConnectionMode: ConnectionMode {
        switch self {
        case .socks5: .proxy
        case .wireGuard: .wireguard
        case .openVPN: .openvpn
        case .nodeMaven: .nodeMaven
        case .direct: .direct
        case .dns: .dns
        case .hybrid: .hybrid
        }
    }
}

// MARK: - Orchestrator Connection State

nonisolated enum OrchestratorConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(NetworkFailure)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .failed(let failure): "Failed: \(failure.localizedDescription)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected, .reconnecting: true
        default: false
        }
    }
}

// MARK: - Connection Metrics

nonisolated struct ConnectionMetrics: Sendable {
    var latencyMs: Int = 0
    var bytesUp: UInt64 = 0
    var bytesDown: UInt64 = 0
    var uptimeSeconds: TimeInterval = 0
    var failureCount: Int = 0
    var successCount: Int = 0

    var totalBytes: UInt64 { bytesUp + bytesDown }

    var successRate: Double {
        let total = failureCount + successCount
        guard total > 0 else { return 0 }
        return Double(successCount) / Double(total)
    }

    var formattedUptime: String {
        let hours = Int(uptimeSeconds) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        let seconds = Int(uptimeSeconds) % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

// MARK: - Connection Log Entry

nonisolated struct ConnectionLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let protocol_: ProxyProtocol
    let event: String
    let detail: String?
    let success: Bool

    init(protocol_: ProxyProtocol, event: String, detail: String? = nil, success: Bool = true) {
        self.timestamp = Date()
        self.protocol_ = protocol_
        self.event = event
        self.detail = detail
        self.success = success
    }
}

// MARK: - DNS Cache Entry

private nonisolated struct DNSCacheEntry: Sendable {
    let resolvedIP: String
    let expiry: Date
    var isExpired: Bool { Date() > expiry }
}

// MARK: - Proxy Orchestrator

@Observable
@MainActor
class ProxyOrchestrator {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = ProxyOrchestrator()

    // MARK: - Dependencies

    private let logger = DebugLogger.shared
    private let connectionPool = ProxyConnectionPool.shared
    private let healthMonitor = ProxyHealthMonitor.shared
    private let rotationService = ProxyRotationService.shared
    private let localProxy = LocalProxyServer.shared
    private let wireProxyBridge = WireProxyBridge.shared
    private let openVPNBridge = OpenVPNProxyBridge.shared
    private let nodeMavenService = NodeMavenService.shared
    private let dnsPool = DNSPoolService.shared

    // MARK: - Observable State

    private(set) var currentState: OrchestratorConnectionState = .disconnected
    private(set) var activeProtocol: ProxyProtocol = .direct
    private(set) var metrics: ConnectionMetrics = ConnectionMetrics()
    private(set) var connectionLog: [ConnectionLogEntry] = []
    private(set) var connectedSince: Date?

    // MARK: - Configuration

    var maxLogEntries: Int = 200
    var connectionTimeoutSeconds: TimeInterval = 30
    var healthCheckIntervalSeconds: TimeInterval = 30
    var dnsCacheTTLSeconds: TimeInterval = 60
    var maxPrewarmConnections: Int = 10

    // MARK: - Private State

    private var dnsCache: [String: DNSCacheEntry] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        let profile = DeviceCapability.performanceProfile
        maxPrewarmConnections = min(20, profile.maxConcurrentPairs / 2)
        logger.log("ProxyOrchestrator initialized", category: .proxy, level: .info)
    }

    // MARK: - Connect

    func connect(protocol proto: ProxyProtocol, config: ProxyConfig? = nil) async throws {
        guard !currentState.isActive else {
            logger.log("Orchestrator: already active on \(activeProtocol.rawValue), disconnecting first", category: .proxy, level: .warning)
            await disconnect()
        }

        currentState = .connecting
        activeProtocol = proto
        appendLog(protocol_: proto, event: "Connecting")
        logger.log("Orchestrator: connecting via \(proto.rawValue)", category: .proxy, level: .info)

        do {
            switch proto {
            case .direct:
                try await connectDirect()
            case .socks5:
                try await connectSOCKS5(config: config)
            case .wireGuard:
                try await connectWireGuard()
            case .openVPN:
                try await connectOpenVPN()
            case .nodeMaven:
                try await connectNodeMaven()
            case .dns:
                try await connectDNS()
            case .hybrid:
                try await connectHybrid(config: config)
            }

            currentState = .connected
            connectedSince = Date()
            metrics.successCount += 1
            rotationService.setUnifiedConnectionMode(proto.toConnectionMode)
            appendLog(protocol_: proto, event: "Connected")
            logger.log("Orchestrator: connected via \(proto.rawValue)", category: .proxy, level: .success)

            startHealthCheckLoop()
        } catch {
            let failure = mapError(error)
            currentState = .failed(failure)
            metrics.failureCount += 1
            appendLog(protocol_: proto, event: "Connection failed", detail: failure.localizedDescription, success: false)
            logger.log("Orchestrator: connection failed – \(failure.localizedDescription)", category: .proxy, level: .error)
            throw failure
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        let proto = activeProtocol
        logger.log("Orchestrator: disconnecting \(proto.rawValue)", category: .proxy, level: .info)

        healthCheckTask?.cancel()
        healthCheckTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        switch proto {
        case .socks5, .hybrid:
            localProxy.stop()
            localProxy.stopHealthMonitoring()
        case .wireGuard:
            wireProxyBridge.stop()
        case .openVPN:
            openVPNBridge.stop()
        default:
            break
        }

        healthMonitor.stopMonitoring()
        updateMetricsOnDisconnect()

        currentState = .disconnected
        connectedSince = nil
        appendLog(protocol_: proto, event: "Disconnected")
        logger.log("Orchestrator: disconnected", category: .proxy, level: .info)
    }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        guard currentState.isActive else { return false }

        let healthy: Bool
        switch activeProtocol {
        case .socks5, .hybrid:
            healthy = localProxy.isRunning && healthMonitor.upstreamHealth.isHealthy
        case .wireGuard:
            healthy = wireProxyBridge.isActive
        case .openVPN:
            healthy = openVPNBridge.isActive
        case .direct, .dns, .nodeMaven:
            await healthMonitor.forceCheck()
            healthy = healthMonitor.upstreamHealth.isHealthy || healthMonitor.upstreamHealth.totalChecks == 0
        }

        if !healthy {
            logger.log("Orchestrator: health check failed for \(activeProtocol.rawValue)", category: .proxy, level: .warning)
            appendLog(protocol_: activeProtocol, event: "Health check failed", success: false)
        }

        if let latency = healthMonitor.upstreamHealth.latencyMs {
            metrics.latencyMs = latency
        }

        return healthy
    }

    // MARK: - Prewarm Connections

    func prewarmConnections(count: Int) async {
        let effectiveCount = min(count, maxPrewarmConnections)
        guard effectiveCount > 0 else { return }

        logger.log("Orchestrator: prewarming \(effectiveCount) connections", category: .proxy, level: .info)

        let upstream: ProxyConfig? = localProxy.isRunning ? localProxy.upstreamProxy : nil
        await connectionPool.prewarmConnections(count: effectiveCount, upstream: upstream)

        appendLog(protocol_: activeProtocol, event: "Prewarmed \(effectiveCount) connections")
        logger.log("Orchestrator: prewarm complete – pool utilization \(String(format: "%.0f%%", connectionPool.poolUtilization * 100))", category: .proxy, level: .success)
    }

    // MARK: - Rotate Proxy

    func rotateProxy(maxRetries: Int = 3) async throws {
        guard currentState.isActive else {
            throw NetworkFailure.connectionRefused
        }

        logger.log("Orchestrator: rotating proxy", category: .proxy, level: .info)
        currentState = .reconnecting
        appendLog(protocol_: activeProtocol, event: "Rotating proxy")

        let target: ProxyRotationService.ProxyTarget = .joe

        for attempt in 1...maxRetries {
            guard let nextProxy = rotationService.nextWorkingProxy(for: target) else {
                currentState = .failed(.proxyRotationExhausted)
                metrics.failureCount += 1
                appendLog(protocol_: activeProtocol, event: "Rotation exhausted", success: false)
                logger.log("Orchestrator: no working proxies available for rotation", category: .proxy, level: .error)
                throw NetworkFailure.proxyRotationExhausted
            }

            localProxy.updateUpstream(nextProxy)
            rotationService.currentProxyIndex += 1

            try? await Task.sleep(for: .milliseconds(500))

            let healthy = await healthCheck()
            if healthy {
                currentState = .connected
                metrics.successCount += 1
                appendLog(protocol_: activeProtocol, event: "Rotated to \(nextProxy.displayString)")
                logger.log("Orchestrator: rotated to \(nextProxy.displayString)", category: .proxy, level: .success)
                return
            }

            rotationService.markProxyFailed(nextProxy)
            metrics.failureCount += 1
            appendLog(protocol_: activeProtocol, event: "Rotation attempt \(attempt) failed for \(nextProxy.displayString)", success: false)
            logger.log("Orchestrator: rotation attempt \(attempt)/\(maxRetries) failed", category: .proxy, level: .warning)
        }

        currentState = .failed(.proxyRotationExhausted)
        logger.log("Orchestrator: rotation exhausted after \(maxRetries) retries", category: .proxy, level: .error)
        throw NetworkFailure.proxyRotationExhausted
    }

    // MARK: - DNS Resolution Cache

    func resolveDNS(_ hostname: String) async -> String? {
        if let cached = dnsCache[hostname], !cached.isExpired {
            return cached.resolvedIP
        }

        let answer = await dnsPool.resolveWithRotation(hostname: hostname)
        guard let ip = answer?.ip else {
            logger.log("Orchestrator: DNS resolution failed for \(hostname)", category: .dns, level: .warning)
            return nil
        }

        dnsCache[hostname] = DNSCacheEntry(
            resolvedIP: ip,
            expiry: Date().addingTimeInterval(dnsCacheTTLSeconds)
        )
        return ip
    }

    func flushDNSCache() {
        let count = dnsCache.count
        dnsCache.removeAll()
        logger.log("Orchestrator: flushed \(count) DNS cache entries", category: .dns, level: .info)
    }

    // MARK: - Diagnostic Summary

    var diagnosticSummary: String {
        let pool = connectionPool
        let health = healthMonitor

        return """
        === Proxy Orchestrator Diagnostics ===
        State: \(currentState.label)
        Protocol: \(activeProtocol.rawValue)
        Uptime: \(metrics.formattedUptime)
        Latency: \(metrics.latencyMs)ms
        Traffic: ↑\(formatBytes(metrics.bytesUp)) ↓\(formatBytes(metrics.bytesDown))
        Success Rate: \(String(format: "%.1f%%", metrics.successRate * 100))
        Failures: \(metrics.failureCount) | Successes: \(metrics.successCount)
        Pool: \(pool.activeCount) active, \(pool.idleCount) idle (\(String(format: "%.0f%%", pool.poolUtilization * 100)) utilization)
        Pool Hit Rate: \(String(format: "%.1f%%", pool.hitRate * 100))
        Health: \(health.upstreamHealth.isHealthy ? "Healthy" : "Unhealthy") (checked \(health.upstreamHealth.totalChecks)x)
        Health Avg Latency: \(health.averageLatencyMs.map { "\($0)ms" } ?? "N/A")
        DNS Cache: \(dnsCache.count) entries
        Log Entries: \(connectionLog.count)
        Local Proxy: \(localProxy.isRunning ? "Running (:\(localProxy.listeningPort))" : "Stopped")
        WireGuard: \(wireProxyBridge.statusLabel)
        OpenVPN: \(openVPNBridge.statusLabel)
        """
    }

    // MARK: - Private — Protocol Connection Handlers

    private func connectDirect() async throws {
        localProxy.updateUpstream(nil)
    }

    private func connectSOCKS5(config: ProxyConfig?) async throws {
        guard let proxy = config ?? rotationService.nextWorkingProxy(for: .joe) else {
            throw NetworkFailure.proxyRotationExhausted
        }
        localProxy.updateUpstream(proxy)
        localProxy.start()
        healthMonitor.startMonitoring(upstream: proxy) { [weak self] in
            Task { @MainActor in
                try? await self?.rotateProxy()
            }
        }
    }

    private func connectWireGuard() async throws {
        guard let wgConfig = rotationService.joeWGConfigs.first else {
            throw NetworkFailure.tunnelEstablishmentFailed
        }
        await wireProxyBridge.start(with: wgConfig)
        guard wireProxyBridge.isActive else {
            throw NetworkFailure.tunnelEstablishmentFailed
        }
        localProxy.enableWireProxyMode(true)
        localProxy.start()
    }

    private func connectOpenVPN() async throws {
        guard let ovpnConfig = rotationService.joeVPNConfigs.first else {
            throw NetworkFailure.tunnelEstablishmentFailed
        }
        await openVPNBridge.start(with: ovpnConfig)
        guard openVPNBridge.isActive else {
            throw NetworkFailure.tunnelEstablishmentFailed
        }
        localProxy.enableOpenVPNProxyMode(true)
        localProxy.start()
    }

    private func connectNodeMaven() async throws {
        let proxy = ProxyConfig(
            host: NodeMavenService.gatewayHost,
            port: NodeMavenService.socks5Port,
            username: nodeMavenService.proxyUsername.isEmpty ? nil : nodeMavenService.proxyUsername,
            password: nodeMavenService.proxyPassword.isEmpty ? nil : nodeMavenService.proxyPassword
        )
        localProxy.updateUpstream(proxy)
        localProxy.start()
        healthMonitor.startMonitoring(upstream: proxy) { [weak self] in
            Task { @MainActor in
                try? await self?.rotateProxy()
            }
        }
    }

    private func connectDNS() async throws {
        localProxy.updateUpstream(nil)
        localProxy.start()
    }

    private func connectHybrid(config: ProxyConfig?) async throws {
        try await connectSOCKS5(config: config)
    }

    // MARK: - Private — Health Check Loop

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthCheckIntervalSeconds ?? 30))
                guard !Task.isCancelled else { break }
                let healthy = await self?.healthCheck() ?? false
                if !healthy {
                    self?.logger.log("Orchestrator: periodic health check failed, attempting reconnect", category: .proxy, level: .warning)
                    await self?.attemptReconnect()
                }
            }
        }
    }

    private func attemptReconnect() async {
        switch currentState {
        case .connected, .reconnecting, .failed:
            break
        default:
            return
        }

        currentState = .reconnecting
        appendLog(protocol_: activeProtocol, event: "Auto-reconnecting")
        logger.log("Orchestrator: attempting auto-reconnect", category: .proxy, level: .info)

        do {
            let proto = activeProtocol
            await disconnect()
            try await connect(protocol: proto)
        } catch {
            currentState = .failed(mapError(error))
            logger.log("Orchestrator: auto-reconnect failed – \(error.localizedDescription)", category: .proxy, level: .error)
        }
    }

    // MARK: - Private — Metrics

    private func updateMetricsOnDisconnect() {
        if let since = connectedSince {
            metrics.uptimeSeconds += Date().timeIntervalSince(since)
        }
        let stats = localProxy.stats
        metrics.bytesUp += stats.bytesUploaded
        metrics.bytesDown += stats.bytesDownloaded
    }

    // MARK: - Private — Logging

    private func appendLog(protocol_: ProxyProtocol, event: String, detail: String? = nil, success: Bool = true) {
        let entry = ConnectionLogEntry(protocol_: protocol_, event: event, detail: detail, success: success)
        connectionLog.append(entry)
        if connectionLog.count > maxLogEntries {
            connectionLog.removeFirst(connectionLog.count - maxLogEntries)
        }
    }

    // MARK: - Private — Error Mapping

    private func mapError(_ error: Error) -> NetworkFailure {
        if let nf = error as? NetworkFailure { return nf }

        let message = error.localizedDescription.lowercased()
        if message.contains("refused") { return .connectionRefused }
        if message.contains("handshake") { return .handshakeFailed }
        if message.contains("auth") { return .authenticationFailed }
        if message.contains("timed out") || message.contains("timeout") { return .timeout }
        if message.contains("dns") || message.contains("resolve") { return .dnsResolutionFailed }
        if message.contains("tunnel") { return .tunnelEstablishmentFailed }
        if message.contains("rate") || message.contains("throttl") { return .rateLimited }
        return .unknown(error.localizedDescription)
    }

    // MARK: - Private — Formatting

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }
}
