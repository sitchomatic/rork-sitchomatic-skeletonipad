import Foundation

// MARK: - Request Type

nonisolated enum AIRequestType: String, CaseIterable, Sendable, Codable {
    case antiDetection
    case automation
    case batchInsight
    case challengeSolving
    case checkpointVerification
    case confidenceAnalysis
    case credentialPriority
    case credentialTriage
    case customTools
    case fingerprintTuning
    case loginURLOptimization
    case batchPreOptimization
    case proxyStrategy
    case interactionGraph
    case runHealth
    case sessionHealth
    case timingOptimization
}

// MARK: - Request Priority

nonisolated enum AIRequestPriority: Int, Comparable, Sendable, Codable {
    case critical = 0
    case normal = 1
    case background = 2

    nonisolated static func < (lhs: AIRequestPriority, rhs: AIRequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Analysis Request

nonisolated struct AIAnalysisRequest: Sendable, Identifiable {
    let id: UUID
    let type: AIRequestType
    let priority: AIRequestPriority
    let payload: [String: String]
    let timestamp: Date
    let ttl: TimeInterval

    init(
        id: UUID = UUID(),
        type: AIRequestType,
        priority: AIRequestPriority = .normal,
        payload: [String: String] = [:],
        timestamp: Date = Date(),
        ttl: TimeInterval = 30.0
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.payload = payload
        self.timestamp = timestamp
        self.ttl = ttl
    }

    var cacheKey: String {
        let sortedPayload = payload.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(type.rawValue)|\(sortedPayload)"
    }
}

// MARK: - Analysis Response

nonisolated struct AIAnalysisResponse: Sendable, Identifiable {
    var id: UUID { requestId }
    let requestId: UUID
    let type: AIRequestType
    let result: String
    let confidence: Double
    let reasoning: String
    let timestamp: Date
    let cached: Bool
}

// MARK: - Cache Entry

private struct CacheEntry: Sendable {
    let response: AIAnalysisResponse
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Queue Statistics

nonisolated struct AIQueueStatistics: Sendable {
    let pendingCount: Int
    let processingCount: Int
    let completedCount: Int
    let cacheHits: Int
    let cacheMisses: Int
    let cacheSize: Int

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0.0 }
        return Double(cacheHits) / Double(total)
    }
}

// MARK: - AI Analysis Engine

@Observable @MainActor
class AIAnalysisEngine {
    nonisolated(unsafe) static let shared = AIAnalysisEngine()

    private let logger = DebugLogger.shared

    // MARK: - Queue State

    private(set) var pendingCount: Int = 0
    private(set) var processingCount: Int = 0
    private(set) var completedCount: Int = 0

    // MARK: - Cache State

    private var cache: [String: CacheEntry] = [:]
    private(set) var cacheHits: Int = 0
    private(set) var cacheMisses: Int = 0
    private let defaultTTL: TimeInterval = 30.0
    private let maxCacheSize: Int

    // MARK: - Concurrency

    private let maxConcurrentProcessing: Int

    // MARK: - Initialization

    private init() {
        let profile = DeviceCapability.performanceProfile
        self.maxConcurrentProcessing = max(2, profile.maxConcurrentPairs / 4)
        self.maxCacheSize = profile.maxConcurrentPairs * 10

        logger.log(
            "AIAnalysisEngine initialized",
            category: .system,
            level: .info,
            detail: "maxConcurrent=\(maxConcurrentProcessing), maxCache=\(maxCacheSize)"
        )
    }

    // MARK: - Submit Single Request

    func submit(_ request: AIAnalysisRequest) async -> AIAnalysisResponse {
        evictExpiredEntries()

        if let cached = lookupCache(for: request) {
            cacheHits += 1
            return cached
        }

        cacheMisses += 1
        pendingCount += 1
        let response = await process(request)
        pendingCount = max(0, pendingCount - 1)
        completedCount += 1
        storeInCache(response: response, ttl: request.ttl, key: request.cacheKey)
        return response
    }

    // MARK: - Submit Batch

    func submitBatch(_ requests: [AIAnalysisRequest]) async -> [AIAnalysisResponse] {
        guard !requests.isEmpty else { return [] }
        evictExpiredEntries()

        let sorted = requests.sorted { $0.priority < $1.priority }

        logger.log(
            "Processing batch of \(sorted.count) requests",
            category: .system,
            level: .info,
            detail: "types=\(Set(sorted.map(\.type.rawValue)).sorted().joined(separator: ", "))"
        )

        var responses: [AIAnalysisResponse] = []
        responses.reserveCapacity(sorted.count)

        // Process concurrently up to maxConcurrentProcessing limit
        var index = 0
        while index < sorted.count {
            let batchEnd = min(index + maxConcurrentProcessing, sorted.count)
            let chunk = Array(sorted[index..<batchEnd])

            let chunkResponses = await withTaskGroup(of: AIAnalysisResponse.self) { group in
                for request in chunk {
                    group.addTask { await self.submit(request) }
                }
                var results: [AIAnalysisResponse] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            responses.append(contentsOf: chunkResponses)
            index = batchEnd
        }

        logger.log(
            "Batch complete: \(responses.count) responses",
            category: .system,
            level: .success
        )

        return responses
    }

    // MARK: - Cache Management

    func clearCache() {
        let previousSize = cache.count
        cache.removeAll()
        logger.log("Cache cleared (\(previousSize) entries removed)", category: .system, level: .warning)
    }

    func resetStatistics() {
        cacheHits = 0
        cacheMisses = 0
        completedCount = 0
        logger.log("Statistics reset", category: .system, level: .warning)
    }

    // MARK: - Queue Statistics

    var statistics: AIQueueStatistics {
        AIQueueStatistics(
            pendingCount: pendingCount,
            processingCount: processingCount,
            completedCount: completedCount,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            cacheSize: cache.count
        )
    }

    // MARK: - Diagnostic Summary

    var diagnosticSummary: String {
        let s = statistics
        return """
        AIAnalysisEngine Diagnostics
        ─────────────────────────────
        Queue: \(s.pendingCount) pending, \(s.processingCount) processing, \(s.completedCount) completed
        Cache: \(s.cacheSize)/\(maxCacheSize) entries, \
        hit rate \(String(format: "%.1f%%", s.cacheHitRate * 100)) \
        (\(s.cacheHits) hits, \(s.cacheMisses) misses)
        Concurrency: max \(maxConcurrentProcessing) concurrent tasks
        """
    }

    // MARK: - Private: Cache Lookup

    private func lookupCache(for request: AIAnalysisRequest) -> AIAnalysisResponse? {
        guard let entry = cache[request.cacheKey], !entry.isExpired else {
            return nil
        }

        let cachedResponse = AIAnalysisResponse(
            requestId: request.id,
            type: entry.response.type,
            result: entry.response.result,
            confidence: entry.response.confidence,
            reasoning: entry.response.reasoning,
            timestamp: Date(),
            cached: true
        )
        return cachedResponse
    }

    private func storeInCache(response: AIAnalysisResponse, ttl: TimeInterval, key: String) {
        if cache.count >= maxCacheSize {
            evictOldestEntry()
        }

        let entry = CacheEntry(
            response: response,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        cache[key] = entry
    }

    private func evictExpiredEntries() {
        let expiredKeys = cache.filter { $0.value.isExpired }.map(\.key)
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
        if !expiredKeys.isEmpty {
            logger.log("Evicted \(expiredKeys.count) expired cache entries", category: .system, level: .info)
        }
    }

    private func evictOldestEntry() {
        guard let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt }) else {
            return
        }
        cache.removeValue(forKey: oldest.key)
    }

    // MARK: - Private: Request Processing

    private func process(_ request: AIAnalysisRequest) async -> AIAnalysisResponse {
        processingCount += 1
        let startTime = CFAbsoluteTimeGetCurrent()

        let (result, confidence, reasoning) = analyze(request)

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        processingCount = max(0, processingCount - 1)

        logger.log(
            "Processed \(request.type.rawValue)",
            category: .system,
            level: .success,
            durationMs: durationMs
        )

        return AIAnalysisResponse(
            requestId: request.id,
            type: request.type,
            result: result,
            confidence: confidence,
            reasoning: reasoning,
            timestamp: Date(),
            cached: false
        )
    }

    // Stub handler — routes to real AI service handlers in future phases
    private func analyze(_ request: AIAnalysisRequest) -> (result: String, confidence: Double, reasoning: String) {
        let context = request.payload["context"] ?? "default"

        let (action, confidence): (String, Double) = switch request.type {
        case .antiDetection:        ("adapt_strategy", 0.85)
        case .automation:           ("orchestrate", 0.90)
        case .batchInsight:         ("tune_batch", 0.80)
        case .challengeSolving:     ("solve_challenge", 0.75)
        case .checkpointVerification: ("verify_checkpoint", 0.88)
        case .confidenceAnalysis:   ("analyze_confidence", 0.82)
        case .credentialPriority:   ("prioritize_credentials", 0.87)
        case .credentialTriage:     ("triage_credentials", 0.83)
        case .customTools:          ("coordinate_tools", 0.78)
        case .fingerprintTuning:    ("tune_fingerprint", 0.86)
        case .loginURLOptimization: ("optimize_url", 0.84)
        case .batchPreOptimization: ("pre_optimize_batch", 0.81)
        case .proxyStrategy:        ("select_proxy", 0.79)
        case .interactionGraph:     ("analyze_graph", 0.76)
        case .runHealth:            ("assess_health", 0.89)
        case .sessionHealth:        ("monitor_session", 0.88)
        case .timingOptimization:   ("optimize_timing", 0.83)
        }

        let reasoning = "\(request.type.rawValue) analysis completed for context: \(context)"
        return (action, confidence, reasoning)
    }
}
