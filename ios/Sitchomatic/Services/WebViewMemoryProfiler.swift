import Foundation

// MARK: - Data Models

nonisolated struct WebViewMemorySnapshot: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let estimatedMemoryMB: Double
    let webViewId: String
    let url: String?
    let isActive: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), estimatedMemoryMB: Double, webViewId: String, url: String?, isActive: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.estimatedMemoryMB = estimatedMemoryMB
        self.webViewId = webViewId
        self.url = url
        self.isActive = isActive
    }
}

nonisolated struct MemoryWaterfallPoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let totalMemoryMB: Double
    let webViewCount: Int
}

// MARK: - WebViewMemoryProfiler

@Observable
@MainActor
final class WebViewMemoryProfiler {
    nonisolated(unsafe) static let shared = WebViewMemoryProfiler()

    private let logger = DebugLogger.shared
    private let maxWaterfallPoints = 100

    // MARK: - Published State

    private(set) var activeSnapshots: [WebViewMemorySnapshot] = []
    private(set) var waterfallHistory: [MemoryWaterfallPoint] = []
    private(set) var peakMemoryMB: Double = 0
    private(set) var isProfiling: Bool = false

    private var profilingTimer: Timer?

    // MARK: - Computed Properties

    var totalEstimatedMemoryMB: Double {
        activeSnapshots.reduce(0) { $0 + $1.estimatedMemoryMB }
    }

    var evictionRecommendations: [String] {
        var recommendations: [String] = []
        let profile = DeviceCapability.performanceProfile

        let systemMB = MemoryMonitor.currentUsageMB()
        if systemMB > profile.memoryThresholdHighMB {
            recommendations.append("System memory above high threshold (\(systemMB) MB) — consider evicting inactive webviews")
        }

        let inactiveViews = activeSnapshots.filter { !$0.isActive }
        if !inactiveViews.isEmpty {
            let inactiveMB = inactiveViews.reduce(0) { $0 + $1.estimatedMemoryMB }
            recommendations.append("\(inactiveViews.count) inactive webview(s) consuming ~\(String(format: "%.1f", inactiveMB)) MB — safe to evict")
        }

        let heavyViews = activeSnapshots.filter { $0.estimatedMemoryMB > 150 }
        for view in heavyViews {
            let label = view.url ?? view.webViewId
            recommendations.append("Heavy webview '\(label)' using ~\(String(format: "%.0f", view.estimatedMemoryMB)) MB")
        }

        if systemMB > profile.memoryThresholdCriticalMB {
            recommendations.append("CRITICAL: Flush screenshot caches and recycle idle webviews immediately")
        }

        if totalEstimatedMemoryMB > Double(profile.memoryThresholdSoftMB) * 0.5 {
            recommendations.append("WebView memory exceeds 50% of soft threshold — monitor closely")
        }

        return recommendations
    }

    var diagnosticSummary: String {
        let active = activeSnapshots.filter(\.isActive).count
        let inactive = activeSnapshots.count - active
        return "WebViews: \(activeSnapshots.count) (active: \(active), idle: \(inactive)) | " +
               "Est. Memory: \(String(format: "%.1f", totalEstimatedMemoryMB)) MB | " +
               "Peak: \(String(format: "%.1f", peakMemoryMB)) MB | " +
               "Waterfall: \(waterfallHistory.count) pts"
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Snapshot Management

    func recordSnapshot(webViewId: String, estimatedMB: Double, url: String?, isActive: Bool) {
        if let index = activeSnapshots.firstIndex(where: { $0.webViewId == webViewId }) {
            activeSnapshots[index] = WebViewMemorySnapshot(
                estimatedMemoryMB: estimatedMB,
                webViewId: webViewId,
                url: url,
                isActive: isActive
            )
        } else {
            activeSnapshots.append(WebViewMemorySnapshot(
                estimatedMemoryMB: estimatedMB,
                webViewId: webViewId,
                url: url,
                isActive: isActive
            ))
        }

        let total = totalEstimatedMemoryMB
        if total > peakMemoryMB {
            peakMemoryMB = total
        }

        logger.log(
            "WebViewMemoryProfiler: recorded \(webViewId) — \(String(format: "%.1f", estimatedMB)) MB (active: \(isActive))",
            category: .webView,
            level: .trace
        )
    }

    func removeSnapshot(webViewId: String) {
        let before = activeSnapshots.count
        activeSnapshots.removeAll { $0.webViewId == webViewId }
        if activeSnapshots.count < before {
            logger.log(
                "WebViewMemoryProfiler: removed snapshot for \(webViewId)",
                category: .webView,
                level: .debug
            )
        }
    }

    // MARK: - Waterfall History

    func captureWaterfallPoint() {
        let point = MemoryWaterfallPoint(
            timestamp: Date(),
            totalMemoryMB: totalEstimatedMemoryMB,
            webViewCount: activeSnapshots.count
        )
        waterfallHistory.append(point)
        if waterfallHistory.count > maxWaterfallPoints {
            waterfallHistory.removeFirst(waterfallHistory.count - maxWaterfallPoints)
        }
    }

    // MARK: - Profiling Control

    func startProfiling(intervalSeconds: TimeInterval = 2.0) {
        guard !isProfiling else { return }
        isProfiling = true

        captureWaterfallPoint()

        profilingTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureWaterfallPoint()
            }
        }

        logger.log(
            "WebViewMemoryProfiler: started profiling (interval: \(intervalSeconds)s)",
            category: .system,
            level: .info
        )
    }

    func stopProfiling() {
        profilingTimer?.invalidate()
        profilingTimer = nil
        isProfiling = false

        logger.log(
            "WebViewMemoryProfiler: stopped profiling — captured \(waterfallHistory.count) points",
            category: .system,
            level: .info
        )
    }

    // MARK: - Eviction

    func triggerEviction() {
        logger.log(
            "WebViewMemoryProfiler: triggering eviction — current est. \(String(format: "%.1f", totalEstimatedMemoryMB)) MB",
            category: .system,
            level: .warning
        )

        UnifiedScreenshotManager.shared.handleMemoryPressure()

        let profile = DeviceCapability.performanceProfile
        ScreenshotCacheService.shared.setMaxCacheCounts(
            memory: profile.screenshotMemoryCacheLimit / 2,
            disk: profile.screenshotDiskCacheLimit / 2
        )

        let inactiveIds = activeSnapshots.filter { !$0.isActive }.map(\.webViewId)
        for id in inactiveIds {
            removeSnapshot(webViewId: id)
        }

        logger.log(
            "WebViewMemoryProfiler: eviction complete — removed \(inactiveIds.count) inactive snapshots, flushed screenshot caches",
            category: .system,
            level: .info
        )
    }
}
