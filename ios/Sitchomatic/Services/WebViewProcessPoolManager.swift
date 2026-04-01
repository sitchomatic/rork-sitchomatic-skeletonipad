import Foundation
@preconcurrency import WebKit

nonisolated enum ProcessPoolMode: Sendable {
    case single
    case tiered(count: Int)
}

@MainActor
final class WebViewProcessPoolManager {
    @MainActor static let shared = WebViewProcessPoolManager()

    private(set) var mode: ProcessPoolMode = .single
    private var singlePool: WKProcessPool = WKProcessPool()
    private var tieredPools: [WKProcessPool] = []
    private let logger = DebugLogger.shared

    private init() {
        configureFromDeviceProfile()
    }

    private func configureFromDeviceProfile() {
        mode = .single
        singlePool = WKProcessPool()
        tieredPools = []
        logger.log("ProcessPoolManager: initialized in SINGLE pool mode (max memory savings)", category: .webView, level: .info)
    }

    func pool(forPairIndex index: Int = 0) -> WKProcessPool {
        switch mode {
        case .single:
            return singlePool
        case .tiered(let count):
            if tieredPools.isEmpty {
                tieredPools = (0..<count).map { _ in WKProcessPool() }
                logger.log("ProcessPoolManager: created \(count) tiered pools", category: .webView, level: .info)
            }
            let tierIndex = index % count
            return tieredPools[tierIndex]
        }
    }

    func switchMode(_ newMode: ProcessPoolMode) {
        mode = newMode
        switch newMode {
        case .single:
            singlePool = WKProcessPool()
            tieredPools = []
            logger.log("ProcessPoolManager: switched to SINGLE pool mode", category: .webView, level: .info)
        case .tiered(let count):
            tieredPools = (0..<count).map { _ in WKProcessPool() }
            logger.log("ProcessPoolManager: switched to TIERED mode with \(count) pools", category: .webView, level: .info)
        }
    }

    func reset() {
        switch mode {
        case .single:
            singlePool = WKProcessPool()
        case .tiered(let count):
            tieredPools = (0..<count).map { _ in WKProcessPool() }
        }
        logger.log("ProcessPoolManager: all pools reset", category: .webView, level: .warning)
    }

    var poolCount: Int {
        switch mode {
        case .single: 1
        case .tiered(let count): count
        }
    }

    var diagnosticSummary: String {
        switch mode {
        case .single:
            "Mode: Single | Pools: 1"
        case .tiered(let count):
            "Mode: Tiered | Pools: \(count)"
        }
    }
}
