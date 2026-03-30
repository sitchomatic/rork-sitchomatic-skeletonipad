import SwiftUI
import WebKit
import Charts

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

@MainActor
final class WebViewMemoryProfiler {
    nonisolated(unsafe) static let shared = WebViewMemoryProfiler()

    private let logger = DebugLogger.shared

    private(set) var snapshots: [WebViewMemorySnapshot] = []
    private(set) var waterfall: [MemoryWaterfallEntry] = []
    private let maxSnapshots = 100
    private let maxWaterfallEntries = 120 // 2 hours at 1 sample/minute

    private var profilingTask: Task<Void, Never>?
    private var isProfilingEnabled = false

    private init() {
        logger.log("WebViewMemoryProfiler: initialized", category: .performance, level: .info)
    }

    // MARK: - Public API

    func startProfiling() {
        guard !isProfilingEnabled else { return }
        isProfilingEnabled = true

        profilingTask = Task {
            while !Task.isCancelled && isProfilingEnabled {
                await captureMemorySnapshot()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        logger.log("WebViewMemoryProfiler: profiling started", category: .performance, level: .info)
    }

    func stopProfiling() {
        isProfilingEnabled = false
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
        snapshots.append(snapshot)

        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
    }

    func getCurrentMemoryUsage() -> (webViewsMB: Double, screenshotsMB: Double, totalMB: Double) {
        let webViewsMB = snapshots.filter { $0.isActive }.reduce(0.0) { $0 + $1.estimatedMemoryMB }
        let screenshotsMB = estimateScreenshotCacheSize()
        return (webViewsMB, screenshotsMB, webViewsMB + screenshotsMB)
    }

    func getEvictionRecommendations() -> [String] {
        var recommendations: [String] = []

        let (_, screenshotsMB, totalMB) = getCurrentMemoryUsage()
        let memoryProfile = DeviceCapability.performanceProfile

        // Check if approaching memory limits
        if totalMB > Double(memoryProfile.safeMemoryMB) * 0.8 {
            recommendations.append("System approaching memory limit (\(Int(totalMB))MB / \(memoryProfile.safeMemoryMB)MB)")

            if screenshotsMB > 50 {
                recommendations.append("Evict screenshot cache (\(Int(screenshotsMB))MB can be freed)")
            }

            let inactiveWebViews = snapshots.filter { !$0.isActive }
            if !inactiveWebViews.isEmpty {
                let inactiveMB = inactiveWebViews.reduce(0.0) { $0 + $1.estimatedMemoryMB }
                recommendations.append("Flush \(inactiveWebViews.count) inactive WebViews (\(Int(inactiveMB))MB)")
            }
        }

        return recommendations
    }

    func getActiveWebViewStats() -> (count: Int, totalMB: Double, avgMB: Double) {
        let active = snapshots.filter { $0.isActive }
        let totalMB = active.reduce(0.0) { $0 + $1.estimatedMemoryMB }
        let avgMB = active.isEmpty ? 0 : totalMB / Double(active.count)
        return (active.count, totalMB, avgMB)
    }

    func clearHistory() {
        snapshots.removeAll()
        waterfall.removeAll()
        logger.log("WebViewMemoryProfiler: history cleared", category: .performance, level: .info)
    }

    // MARK: - Private Implementation

    private func captureMemorySnapshot() async {
        let (webViewsMB, screenshotsMB, totalMB) = getCurrentMemoryUsage()
        let activeCount = snapshots.filter { $0.isActive }.count

        let entry = MemoryWaterfallEntry(
            totalMemoryMB: totalMB,
            webViewCount: activeCount,
            screenshotCacheMB: screenshotsMB
        )
        waterfall.append(entry)

        if waterfall.count > maxWaterfallEntries {
            waterfall.removeFirst(waterfall.count - maxWaterfallEntries)
        }

        // Check for high memory and log warnings
        let memoryProfile = DeviceCapability.performanceProfile
        if totalMB > Double(memoryProfile.safeMemoryMB) * 0.9 {
            logger.log("WebViewMemoryProfiler: HIGH MEMORY WARNING — \(Int(totalMB))MB / \(memoryProfile.safeMemoryMB)MB", category: .performance, level: .warning)

            // Auto-evict if critical
            if totalMB > Double(memoryProfile.safeMemoryMB) {
                await evictScreenshotCache()
            }
        }
    }

    private func estimateScreenshotCacheSize() -> Double {
        // Placeholder - would integrate with UnifiedScreenshotManager
        return 0.0
    }

    private func evictScreenshotCache() async {
        logger.log("WebViewMemoryProfiler: evicting screenshot cache due to memory pressure", category: .performance, level: .warning)
        // Would call UnifiedScreenshotManager.shared.evictImageCache()
    }
}

// MARK: - WebView Memory Profiler View

struct WebViewMemoryProfilerView: View {
    @State private var profiler = WebViewMemoryProfiler.shared
    @State private var refreshTrigger = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Stats
                let (webViewsMB, screenshotsMB, totalMB) = profiler.getCurrentMemoryUsage()
                let (activeCount, activeTotalMB, avgMB) = profiler.getActiveWebViewStats()
                let memoryProfile = DeviceCapability.performanceProfile

                VStack(spacing: 12) {
                    Text("WebView Memory Profiler")
                        .font(.title2.bold())

                    HStack(spacing: 20) {
                        MemoryStatCard(
                            title: "Total Memory",
                            value: "\(Int(totalMB))MB",
                            subtitle: "of \(memoryProfile.safeMemoryMB)MB",
                            color: memoryColor(current: totalMB, max: Double(memoryProfile.safeMemoryMB))
                        )

                        MemoryStatCard(
                            title: "Active WebViews",
                            value: "\(activeCount)",
                            subtitle: "\(Int(activeTotalMB))MB",
                            color: .blue
                        )

                        MemoryStatCard(
                            title: "Avg per WebView",
                            value: "\(Int(avgMB))MB",
                            subtitle: "estimated",
                            color: .purple
                        )
                    }
                }
                .padding()

                // Memory Waterfall Chart
                if !profiler.waterfall.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Memory Usage Over Time")
                            .font(.headline)
                            .padding(.horizontal)

                        Chart(profiler.waterfall) { entry in
                            LineMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Memory", entry.totalMemoryMB)
                            )
                            .foregroundStyle(.blue)

                            AreaMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Memory", entry.totalMemoryMB)
                            )
                            .foregroundStyle(.blue.opacity(0.2))
                        }
                        .frame(height: 200)
                        .chartYAxisLabel("Memory (MB)")
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Eviction Recommendations
                let recommendations = profiler.getEvictionRecommendations()
                if !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Memory Recommendations", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        ForEach(recommendations, id: \.self) { recommendation in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(recommendation)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Per-WebView Breakdown
                if !profiler.snapshots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active WebViews")
                            .font(.headline)
                            .padding(.horizontal)

                        let activeSnapshots = Array(profiler.snapshots.filter { $0.isActive }.suffix(10))
                        ForEach(activeSnapshots) { snapshot in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snapshot.webViewId.prefix(8))
                                        .font(.subheadline.monospaced())
                                    if let url = snapshot.url {
                                        Text(url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text("\(Int(snapshot.estimatedMemoryMB))MB")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.blue)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            profiler.startProfiling()
        }
        .onDisappear {
            profiler.stopProfiling()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshTrigger.toggle()
            }
        }
    }

    private func memoryColor(current: Double, max: Double) -> Color {
        let ratio = current / max
        if ratio > 0.9 { return .red }
        if ratio > 0.75 { return .orange }
        return .green
    }
}

struct MemoryStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
