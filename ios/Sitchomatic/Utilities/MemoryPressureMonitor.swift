import Foundation
import UIKit

/// Five-tier memory pressure monitor with escalation tracking.
/// Registers for UIKit memory warnings and dispatches typed cleanup handlers.
@MainActor
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private var observers: [@MainActor (MemoryTier) -> Void] = []
    private var isRegistered: Bool = false
    private var lastTierTriggered: MemoryTier = .normal
    private(set) var tierEscalationCount: Int = 0

    nonisolated enum MemoryTier: Int, Sendable, Comparable, CustomStringConvertible {
        case normal = 0
        case elevated = 1
        case warning = 2
        case critical = 3
        case severe = 4

        nonisolated static func < (lhs: MemoryTier, rhs: MemoryTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        nonisolated var description: String {
            switch self {
            case .normal: "NORMAL"
            case .elevated: "ELEVATED"
            case .warning: "WARNING"
            case .critical: "CRITICAL"
            case .severe: "SEVERE"
            }
        }
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning(tier: .critical)
            }
        }
    }

    /// Register a typed memory warning handler that receives the current pressure tier.
    func onMemoryWarning(_ handler: @escaping @MainActor (MemoryTier) -> Void) {
        observers.append(handler)
    }

    /// Manually trigger a memory warning at the specified tier.
    func trigger(tier: MemoryTier) {
        handleMemoryWarning(tier: tier)
    }

    private func handleMemoryWarning(tier: MemoryTier) {
        guard tier > .normal else { return }

        if tier > lastTierTriggered {
            tierEscalationCount += 1
        }
        lastTierTriggered = tier

        DebugLogger.shared.log("MEMORY \(tier) — triggering \(observers.count) cleanup handlers (escalations: \(tierEscalationCount))", category: .system, level: tier >= .critical ? .critical : .warning)

        for handler in observers {
            handler(tier)
        }

        if tier >= .severe {
            DebugLogger.shared.log("MemoryMonitor: SEVERE tier — additional aggressive cleanup", category: .system, level: .critical)
            ScreenshotCache.shared.clearAll()
            URLCache.shared.removeAllCachedResponses()
            URLCache.shared.memoryCapacity = 0

            PersistentFileStorageService.shared.forceSave()
            LoginViewModel.shared.persistCredentialsNow()
            PPSRAutomationViewModel.shared.persistCardsNow()
        }
    }

    var diagnosticSummary: String {
        "MemoryMonitor: tier=\(lastTierTriggered) observers=\(observers.count) escalations=\(tierEscalationCount)"
    }
}
