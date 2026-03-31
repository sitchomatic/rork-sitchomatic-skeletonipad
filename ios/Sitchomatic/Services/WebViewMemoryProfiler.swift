import Foundation

// MARK: - Memory Profile Data

nonisolated struct WebViewMemorySnapshot: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let webViewId: String
    let estimatedMemoryMB: Double
    let isActive: Bool
    let url: String?

    init(webViewId: String, estimatedMemoryMB: Double, isActive: Bool, url: String?) {
        self.id = UUID()
        self.timestamp = Date()
        self.webViewId = webViewId
        self.estimatedMemoryMB = estimatedMemoryMB
        self.isActive = isActive
        self.url = url
    }
}

nonisolated struct MemoryWaterfallEntry: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let totalMemoryMB: Double
    let webViewCount: Int
    let screenshotCacheMB: Double

    init(totalMemoryMB: Double, webViewCount: Int, screenshotCacheMB: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.totalMemoryMB = totalMemoryMB
        self.webViewCount = webViewCount
        self.screenshotCacheMB = screenshotCacheMB
    }
}

// MARK: - WebView Memory Profiler Service

@Observable
@MainActor
final class WebViewMemoryProfiler {
    nonisolated(unsafe) static let shared = WebViewMemoryProfiler()

    private let logger = DebugLogger.shared

    // MARK: - Public State

    private(set) var activeSnapshots: [WebViewMemorySnapshot] = []
    private(set) var waterfallHistory: [MemoryWaterfallEntry] = []
    private(set) var isProfiling: Bool = false
    private(set) var peakMemoryMB: Double = 0

    var totalEstimatedMemoryMB: Double {
        activeSnapshots.filter { $0.isActive }.reduce(0.0) { $0 + $1.estimatedMemoryMB }
    }

    var evictionRecommendations: [String] {
        getEvictionRecommendations()
    }

    var diagnosticSummary: String {
        let (webViewsMB, screenshotsMB, totalMB) = getCurrentMemoryUsage()
        let activeCount = activeSnapshots.filter { $0.isActive }.count
        let profile = DeviceCapability.performanceProfile
        return "WebViews: \(activeCount) (\(Int(webViewsMB))MB) | Screenshots: \(Int(screenshotsMB))MB | Total: \(Int(totalMB))MB / \(profile.memoryThresholdSoftMB)MB soft | Peak: \(Int(peakMemoryMB))MB"
    }

    // MARK: - Private

    private let maxSnapshots = 100
    private let maxWaterfallEntries = 120
    private var profilingTask: Task<Void, Never>?

    private init() {
        logger.log("WebViewMemoryProfiler: initialized", category: .performance, level: .info)
    }

    // MARK: - Public API

    func startProfiling() {
        guard !isProfiling else { return }
        isProfiling = true

        profilingTask = Task {
            while !Task.isCancelled && isProfiling {
                captureWaterfallPoint()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        logger.log("WebViewMemoryProfiler: profiling started", category: .performance, level: .info)
    }

    func stopProfiling() {
        isProfiling = false
        profilingTask?.cancel()
        profilingTask = nil
        logger.log("WebViewMemoryProfiler: profiling stopped", category: .performance, level: .info)
    }

    func recordWebView(id: String, estimatedMB: Double, isActive: Bool, url: String?) {
        let snapshot = WebViewMemorySnapshot(
            webViewId: id,
            estimatedMemoryMB: estimatedMB,
            isActive: isActive,
            url: url
        )
        activeSnapshots.append(snapshot)

        if activeSnapshots.count > maxSnapshots {
            activeSnapshots.removeFirst(activeSnapshots.count - maxSnapshots)
        }
    }

    func getCurrentMemoryUsage() -> (webViewsMB: Double, screenshotsMB: Double, totalMB: Double) {
        let webViewsMB = activeSnapshots.filter { $0.isActive }.reduce(0.0) { $0 + $1.estimatedMemoryMB }
        let screenshotsMB = estimateScreenshotCacheSize()
        return (webViewsMB, screenshotsMB, webViewsMB + screenshotsMB)
    }

    func captureWaterfallPoint() {
        let (_, screenshotsMB, totalMB) = getCurrentMemoryUsage()
        let activeCount = activeSnapshots.filter { $0.isActive }.count

        if totalMB > peakMemoryMB {
            peakMemoryMB = totalMB
        }

        let entry = MemoryWaterfallEntry(
            totalMemoryMB: totalMB,
            webViewCount: activeCount,
            screenshotCacheMB: screenshotsMB
        )
        waterfallHistory.append(entry)

        if waterfallHistory.count > maxWaterfallEntries {
            waterfallHistory.removeFirst(waterfallHistory.count - maxWaterfallEntries)
        }

        // Check for high memory and log warnings
        let memoryProfile = DeviceCapability.performanceProfile
        if totalMB > Double(memoryProfile.memoryThresholdSoftMB) * 0.9 {
            logger.log("WebViewMemoryProfiler: HIGH MEMORY WARNING — \(Int(totalMB))MB / \(memoryProfile.memoryThresholdSoftMB)MB", category: .performance, level: .warning)

            if totalMB > Double(memoryProfile.memoryThresholdHighMB) {
                triggerEviction()
            }
        }
    }

    func triggerEviction() {
        logger.log("WebViewMemoryProfiler: evicting screenshot cache due to memory pressure", category: .performance, level: .warning)
        UnifiedScreenshotManager.shared.handleMemoryPressure()
        ScreenshotCache.shared.setMaxCacheCounts(memory: 10, disk: 200)
    }

    func clearHistory() {
        activeSnapshots.removeAll()
        waterfallHistory.removeAll()
        peakMemoryMB = 0
        logger.log("WebViewMemoryProfiler: history cleared", category: .performance, level: .info)
    }

    // MARK: - Private Implementation

    private func getEvictionRecommendations() -> [String] {
        var recommendations: [String] = []

        let (_, screenshotsMB, totalMB) = getCurrentMemoryUsage()
        let memoryProfile = DeviceCapability.performanceProfile

        if totalMB > Double(memoryProfile.memoryThresholdSoftMB) * 0.8 {
            recommendations.append("System approaching memory limit (\(Int(totalMB))MB / \(memoryProfile.memoryThresholdSoftMB)MB)")

            if screenshotsMB > 50 {
                recommendations.append("Evict screenshot cache (\(Int(screenshotsMB))MB can be freed)")
            }

            let inactiveWebViews = activeSnapshots.filter { !$0.isActive }
            if !inactiveWebViews.isEmpty {
                let inactiveMB = inactiveWebViews.reduce(0.0) { $0 + $1.estimatedMemoryMB }
                recommendations.append("Flush \(inactiveWebViews.count) inactive WebViews (\(Int(inactiveMB))MB)")
            }
        }

        return recommendations
    }

    private func estimateScreenshotCacheSize() -> Double {
        return 0.0
    }
}
