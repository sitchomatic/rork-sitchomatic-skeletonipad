import Foundation
import Network

// MARK: - Network Failure Types

enum NetworkFailure: Error, Sendable {
    case proxyConnectionFailed(reason: String)
    case proxyTimeout
    case proxyAuthenticationFailed
    case dnsResolutionFailed(host: String)
    case networkUnreachable
    case socks5HandshakeFailed
    case wireGuardTunnelFailed
    case openVPNConnectionFailed
    case healthCheckFailed(proxy: String)
    case allProxiesExhausted
    case configurationInvalid

    var localizedDescription: String {
        switch self {
        case .proxyConnectionFailed(let reason): return "Proxy connection failed: \(reason)"
        case .proxyTimeout: return "Proxy connection timeout"
        case .proxyAuthenticationFailed: return "Proxy authentication failed"
        case .dnsResolutionFailed(let host): return "DNS resolution failed for \(host)"
        case .networkUnreachable: return "Network unreachable"
        case .socks5HandshakeFailed: return "SOCKS5 handshake failed"
        case .wireGuardTunnelFailed: return "WireGuard tunnel failed"
        case .openVPNConnectionFailed: return "OpenVPN connection failed"
        case .healthCheckFailed(let proxy): return "Health check failed for \(proxy)"
        case .allProxiesExhausted: return "All proxy connections exhausted"
        case .configurationInvalid: return "Proxy configuration invalid"
        }
    }
}

// MARK: - Proxy Types

enum ProxyProtocol: String, Sendable {
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



nonisolated struct ProxyHealthStatus: Sendable {
    let proxy: ProxyConfig
    let isHealthy: Bool
    let lastCheckTime: Date
    let latencyMs: Int
    let consecutiveFailures: Int
    let successRate: Double
}


// MARK: - Proxy Orchestrator

@MainActor
final class ProxyOrchestrator {
    static let shared = ProxyOrchestrator()

    private let logger = DebugLogger.shared

    // Connection pool
    private var availableProxies: [ProxyConfig] = []
    private var activeConnections: [UUID: ProxyConfig] = [:]
    private var healthStatus: [UUID: ProxyHealthStatus] = [:]
    private var connectionPool: [ProxyProtocol: Any] = [:] // Protocol-specific handlers

    // DNS cache
    private var dnsCache: [String: DNSCacheEntry] = [:]
    private let dnsCacheTTL: TimeInterval = 300 // 5 minutes

    // Health monitoring
    private let healthCheckInterval: TimeInterval = 30
    private let maxConsecutiveFailures = 3
    private var healthCheckTask: Task<Void, Never>?

    // Statistics
    private var totalConnections: Int = 0
    private var successfulConnections: Int = 0
    private var failedConnections: Int = 0
    private var averageLatencyMs: Double = 0

    private init() {
        logger.log("ProxyOrchestrator: initialized", category: .network, level: .info)
    }

    // MARK: - Public API

    func configure(proxies: [ProxyConfig]) {
        availableProxies = proxies
        logger.log("ProxyOrchestrator: configured with \(proxies.count) proxies", category: .network, level: .info)

        // Initialize health status for all proxies
        for proxy in proxies {
            healthStatus[proxy.id] = ProxyHealthStatus(
                proxy: proxy,
                isHealthy: true,
                lastCheckTime: .distantPast,
                latencyMs: 0,
                consecutiveFailures: 0,
                successRate: 1.0
            )
        }

        // Start health monitoring
        startHealthMonitoring()
    }

    func addProxy(_ proxy: ProxyConfig) {
        availableProxies.append(proxy)
        healthStatus[proxy.id] = ProxyHealthStatus(
            proxy: proxy,
            isHealthy: true,
            lastCheckTime: .distantPast,
            latencyMs: 0,
            consecutiveFailures: 0,
            successRate: 1.0
        )
        logger.log("ProxyOrchestrator: added proxy \(proxy.displayString)", category: .network, level: .info)
    }

    func removeProxy(id: UUID) {
        availableProxies.removeAll { $0.id == id }
        healthStatus.removeValue(forKey: id)
        activeConnections.removeValue(forKey: id)
        logger.log("ProxyOrchestrator: removed proxy \(id.uuidString.prefix(8))", category: .network, level: .info)
    }

    func getHealthyProxy(preferredProtocol: ProxyProtocol? = nil) -> ProxyConfig? {
        let healthy = availableProxies.filter { proxy in
            guard let status = healthStatus[proxy.id] else { return false }
            return status.isHealthy && status.consecutiveFailures < maxConsecutiveFailures
        }

        guard !healthy.isEmpty else {
            logger.log("ProxyOrchestrator: no healthy proxies available", category: .network, level: .warning)
            return nil
        }

        // Select proxy with best health metrics
        return healthy.sorted { a, b in
            guard let statusA = healthStatus[a.id], let statusB = healthStatus[b.id] else { return false }
            // Prioritize by success rate, then latency
            if abs(statusA.successRate - statusB.successRate) > 0.1 {
                return statusA.successRate > statusB.successRate
            }
            return statusA.latencyMs < statusB.latencyMs
        }.first
    }

    func resolveDNS(host: String) async -> String? {
        // Check cache first
        if let cached = dnsCache[host], !cached.isExpired {
            logger.log("ProxyOrchestrator: DNS cache HIT for \(host) → \(cached.resolvedIP)", category: .network, level: .debug)
            return cached.resolvedIP
        }

        // Resolve DNS
        logger.log("ProxyOrchestrator: resolving DNS for \(host)", category: .network, level: .debug)

        do {
            guard let url = URL(string: "https://\(host)") else { return nil }
            guard let hostString = url.host else { return nil }

            let parameters = NWParameters()
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(hostString), port: .https)
            let connection = NWConnection(to: endpoint, using: parameters)

            return await withCheckedContinuation { continuation in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let path = connection.currentPath, let endpoint = path.remoteEndpoint {
                            if case .hostPort(let host, _) = endpoint {
                                let ip = "\(host)"
                                Task { @MainActor in
                                    self.cacheDNS(host: hostString, ip: ip)
                                }
                                connection.cancel()
                                continuation.resume(returning: ip)
                                return
                            }
                        }
                        connection.cancel()
                        continuation.resume(returning: hostString)
                    case .failed(_):
                        connection.cancel()
                        continuation.resume(returning: nil)
                    default:
                        break
                    }
                }
                connection.start(queue: .global())

                // Timeout after 5 seconds
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    connection.cancel()
                }
            }
        }
    }

    func prewarmConnections(count: Int = 5) async {
        logger.log("ProxyOrchestrator: prewarming \(count) connections", category: .network, level: .info)

        let proxiesToWarm = Array(availableProxies.prefix(count))

        await withTaskGroup(of: Void.self) { group in
            for proxy in proxiesToWarm {
                group.addTask {
                    await self.testProxyConnection(proxy)
                }
            }
        }

        logger.log("ProxyOrchestrator: prewarming complete", category: .network, level: .info)
    }

    func getStats() -> (total: Int, healthy: Int, avgLatency: Double, successRate: Double) {
        let healthy = healthStatus.values.filter { $0.isHealthy && $0.consecutiveFailures < maxConsecutiveFailures }.count
        let successRate = totalConnections > 0 ? Double(successfulConnections) / Double(totalConnections) : 0
        return (availableProxies.count, healthy, averageLatencyMs, successRate)
    }

    func getAllHealthStatus() -> [ProxyHealthStatus] {
        Array(healthStatus.values).sorted { $0.successRate > $1.successRate }
    }

    func recordConnectionResult(proxyId: UUID, success: Bool, latencyMs: Int) {
        totalConnections += 1
        if success {
            successfulConnections += 1
        } else {
            failedConnections += 1
        }

        // Update average latency
        if success {
            let total = Double(successfulConnections)
            averageLatencyMs = (averageLatencyMs * (total - 1) + Double(latencyMs)) / total
        }

        // Update health status
        guard var status = healthStatus[proxyId] else { return }

        if success {
            status = ProxyHealthStatus(
                proxy: status.proxy,
                isHealthy: true,
                lastCheckTime: Date(),
                latencyMs: latencyMs,
                consecutiveFailures: 0,
                successRate: min(status.successRate + 0.05, 1.0)
            )
        } else {
            status = ProxyHealthStatus(
                proxy: status.proxy,
                isHealthy: status.consecutiveFailures + 1 < maxConsecutiveFailures,
                lastCheckTime: Date(),
                latencyMs: status.latencyMs,
                consecutiveFailures: status.consecutiveFailures + 1,
                successRate: max(status.successRate - 0.1, 0.0)
            )
        }

        healthStatus[proxyId] = status
    }

    func stopHealthMonitoring() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        logger.log("ProxyOrchestrator: health monitoring stopped", category: .network, level: .info)
    }

    // MARK: - Private Implementation

    private func startHealthMonitoring() {
        stopHealthMonitoring()

        healthCheckTask = Task {
            while !Task.isCancelled {
                await performHealthChecks()
                try? await Task.sleep(for: .seconds(healthCheckInterval))
            }
        }

        logger.log("ProxyOrchestrator: health monitoring started (interval: \(Int(healthCheckInterval))s)", category: .network, level: .info)
    }

    private func performHealthChecks() async {
        let proxiesToCheck = availableProxies.prefix(10) // Check up to 10 proxies per cycle

        await withTaskGroup(of: Void.self) { group in
            for proxy in proxiesToCheck {
                group.addTask {
                    await self.testProxyConnection(proxy)
                }
            }
        }
    }

    private func testProxyConnection(_ proxy: ProxyConfig) async {
        let start = Date()

        // Delegate to existing health monitor for connectivity status
        let healthMonitor = ProxyHealthMonitor.shared
        let success = healthMonitor.upstreamHealth.isHealthy
        let latencyMs = healthMonitor.upstreamHealth.latencyMs ?? Int(Date().timeIntervalSince(start) * 1000)

        recordConnectionResult(proxyId: proxy.id, success: success, latencyMs: max(latencyMs, 1))

        if !success {
            logger.log("ProxyOrchestrator: health check FAILED for \(proxy.displayString)", category: .network, level: .warning)
        }
    }

    private func cacheDNS(host: String, ip: String) {
        let entry = DNSCacheEntry(
            resolvedIP: ip,
            expiry: Date().addingTimeInterval(dnsCacheTTL)
        )
        dnsCache[host] = entry

        if dnsCache.count > 100 {
            dnsCache = dnsCache.filter { !$0.value.isExpired }
        }
    }
}
