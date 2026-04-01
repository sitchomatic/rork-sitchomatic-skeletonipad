import Foundation
import UIKit

enum DeviceCapability {

    static let totalRAMBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    static let totalRAMGB: Int = Int(totalRAMBytes / (1024 * 1024 * 1024))
    static let processorCount: Int = ProcessInfo.processInfo.activeProcessorCount

    static let isIPad: Bool = UIDevice.current.userInterfaceIdiom == .pad

    static let isHighPerformanceDevice: Bool = totalRAMGB >= 8 && processorCount >= 6

    static let isM5Class: Bool = totalRAMGB >= 16 && processorCount >= 8

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

    static var diagnosticSummary: String {
        """
        Device: \(isIPad ? "iPad" : "iPhone")
        RAM: \(totalRAMGB)GB (\(totalRAMBytes / (1024 * 1024))MB)
        Cores: \(processorCount)
        Class: \(isM5Class ? "M5+" : isHighPerformanceDevice ? "High Performance" : "Standard")
        Max Pairs: \(performanceProfile.maxConcurrentPairs)
        Recycler Pool: \(performanceProfile.maxRecycledWebViews)
        Memory Soft: \(performanceProfile.memoryThresholdSoftMB)MB
        Memory Emergency: \(performanceProfile.memoryThresholdEmergencyMB)MB
        Screenshot Quality: \(performanceProfile.screenshotCompressionQuality)
        Stability Checks: \(performanceProfile.automationStabilityChecks)
        """
    }
}
