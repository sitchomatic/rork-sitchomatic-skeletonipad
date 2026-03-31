import Foundation
import UIKit

/// Static device classification and performance profiling.
/// Provides hardware-aware thresholds for concurrency, memory, and caching.
enum DeviceCapability {

    static let totalRAMBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    static let totalRAMGB: Int = Int(totalRAMBytes / (1024 * 1024 * 1024))
    static let processorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    static let isIPad: Bool = UIDevice.current.userInterfaceIdiom == .pad

    /// M4-class iPad Pro / high-end devices (≥12 GB RAM, ≥8 cores)
    static let isM4Class: Bool = totalRAMGB >= 12 && processorCount >= 8

    /// M5-class or future ultra-high-end devices (≥16 GB RAM, ≥8 cores)
    static let isM5Class: Bool = totalRAMGB >= 16 && processorCount >= 8

    /// High-performance devices (≥8 GB RAM, ≥6 cores) — includes M2/M3 iPads
    static let isHighPerformanceDevice: Bool = totalRAMGB >= 8 && processorCount >= 6

    struct PerformanceProfile: Sendable {
        let maxConcurrentPairs: Int
        let memoryThresholdSoftMB: Int
        let memoryThresholdHighMB: Int
        let memoryThresholdCriticalMB: Int
        let memoryThresholdEmergencyMB: Int
        let recommendedMaxConcurrency: Int
        let webViewPrewarmCount: Int
        let maxRecycledWebViews: Int
        let screenshotMemoryCacheLimit: Int
        let screenshotDiskCacheLimit: Int
        let screenshotCompressionQuality: Double
        let automationStabilityChecks: Int
    }

    static let performanceProfile: PerformanceProfile = {
        if isM5Class {
            return PerformanceProfile(
                maxConcurrentPairs: 40,
                memoryThresholdSoftMB: 6000,
                memoryThresholdHighMB: 9000,
                memoryThresholdCriticalMB: 12000,
                memoryThresholdEmergencyMB: 14000,
                recommendedMaxConcurrency: 20,
                webViewPrewarmCount: 10,
                maxRecycledWebViews: 20,
                screenshotMemoryCacheLimit: 500,
                screenshotDiskCacheLimit: 3000,
                screenshotCompressionQuality: 0.4,
                automationStabilityChecks: 3
            )
        } else if isM4Class {
            return PerformanceProfile(
                maxConcurrentPairs: 30,
                memoryThresholdSoftMB: 4500,
                memoryThresholdHighMB: 7000,
                memoryThresholdCriticalMB: 9500,
                memoryThresholdEmergencyMB: 11000,
                recommendedMaxConcurrency: 15,
                webViewPrewarmCount: 8,
                maxRecycledWebViews: 16,
                screenshotMemoryCacheLimit: 400,
                screenshotDiskCacheLimit: 2000,
                screenshotCompressionQuality: 0.4,
                automationStabilityChecks: 3
            )
        } else if isHighPerformanceDevice {
            return PerformanceProfile(
                maxConcurrentPairs: 20,
                memoryThresholdSoftMB: 3000,
                memoryThresholdHighMB: 5000,
                memoryThresholdCriticalMB: 7000,
                memoryThresholdEmergencyMB: 9000,
                recommendedMaxConcurrency: 10,
                webViewPrewarmCount: 5,
                maxRecycledWebViews: 12,
                screenshotMemoryCacheLimit: 300,
                screenshotDiskCacheLimit: 1500,
                screenshotCompressionQuality: 0.4,
                automationStabilityChecks: 3
            )
        } else {
            return PerformanceProfile(
                maxConcurrentPairs: 10,
                memoryThresholdSoftMB: 1500,
                memoryThresholdHighMB: 2500,
                memoryThresholdCriticalMB: 4000,
                memoryThresholdEmergencyMB: 5000,
                recommendedMaxConcurrency: 5,
                webViewPrewarmCount: 2,
                maxRecycledWebViews: 4,
                screenshotMemoryCacheLimit: 150,
                screenshotDiskCacheLimit: 500,
                screenshotCompressionQuality: 0.4,
                automationStabilityChecks: 4
            )
        }
    }()

    static var deviceClass: String {
        if isM5Class { return "M5+" }
        if isM4Class { return "M4" }
        if isHighPerformanceDevice { return "High Performance" }
        return "Standard"
    }

    static var diagnosticSummary: String {
        """
        Device: \(isIPad ? "iPad" : "iPhone")
        RAM: \(totalRAMGB)GB (\(totalRAMBytes / (1024 * 1024))MB)
        Cores: \(processorCount)
        Class: \(deviceClass)
        Max Pairs: \(performanceProfile.maxConcurrentPairs)
        Recycler Pool: \(performanceProfile.maxRecycledWebViews)
        Memory Soft: \(performanceProfile.memoryThresholdSoftMB)MB
        Memory Emergency: \(performanceProfile.memoryThresholdEmergencyMB)MB
        Screenshot Quality: \(performanceProfile.screenshotCompressionQuality)
        Stability Checks: \(performanceProfile.automationStabilityChecks)
        """
    }
}
