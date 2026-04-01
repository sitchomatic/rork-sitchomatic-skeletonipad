import Foundation

// MARK: - Request Types

enum AIRequestPriority: Int, Comparable, Sendable {
    case critical = 0
    case normal = 1
    case background = 2

    static func < (lhs: AIRequestPriority, rhs: AIRequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AIAnalysisRequest: Sendable {
    let id: UUID
    let systemPrompt: String
    let userPrompt: String
    let priority: AIRequestPriority
    let model: GrokModel
    let temperature: Double
    let jsonMode: Bool
    let cacheKey: String?
    let timestamp: Date

    init(
        systemPrompt: String,
        userPrompt: String,
        priority: AIRequestPriority = .normal,
        model: GrokModel = .standard,
        temperature: Double = 0.3,
        jsonMode: Bool = false,
        cacheKey: String? = nil
    ) {
        self.id = UUID()
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.priority = priority
        self.model = model
        self.temperature = temperature
        self.jsonMode = jsonMode
        self.cacheKey = cacheKey
        self.timestamp = Date()
    }
}

nonisolated struct CachedResponse: Sendable {
    let response: String
    let cachedAt: Date
    let expiresAt: Date
}

nonisolated struct AIAnalysisStats: Sendable {
    var totalRequests: Int = 0
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var queuedRequests: Int = 0
    var processingRequests: Int = 0
    var completedRequests: Int = 0
    var failedRequests: Int = 0
    var avgResponseTimeMs: Double = 0

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Double(cacheHits) / Double(total)
    }
}

// MARK: - Unified AI Analysis Engine

@MainActor
final class AIAnalysisEngine {
    static let shared = AIAnalysisEngine()

    private let logger = DebugLogger.shared
    private let grokService = RorkToolkitService.shared

    private let cacheTTL: TimeInterval = 30 // 30 seconds cache
    private let maxQueueSize = 1000
    private let maxConcurrentRequests = 3

    private var requestQueue: [AIAnalysisRequest] = []
    private var responseCache: [String: CachedResponse] = [:]
    private var stats = AIAnalysisStats()
    private var processingCount = 0

    private init() {
        logger.log("AIAnalysisEngine: initialized with cache TTL=\(Int(cacheTTL))s, maxConcurrent=\(maxConcurrentRequests)", category: .automation, level: .info)
    }

    // MARK: - Public API

    func analyze(
        systemPrompt: String,
        userPrompt: String,
        priority: AIRequestPriority = .normal,
        model: GrokModel = .standard,
        temperature: Double = 0.3,
        jsonMode: Bool = false,
        enableCache: Bool = true
    ) async -> String? {
        let cacheKey = enableCache ? generateCacheKey(systemPrompt: systemPrompt, userPrompt: userPrompt, model: model) : nil

        // Check cache first
        if let cacheKey, let cached = getCachedResponse(for: cacheKey) {
            stats.cacheHits += 1
            logger.log("AIAnalysisEngine: cache HIT for request (saved \(Int(Date().timeIntervalSince(cached.cachedAt) * 1000))ms)", category: .evaluation, level: .debug)
            return cached.response
        }

        if enableCache {
            stats.cacheMisses += 1
        }

        let request = AIAnalysisRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            priority: priority,
            model: model,
            temperature: temperature,
            jsonMode: jsonMode,
            cacheKey: cacheKey
        )

        return await processRequest(request)
    }

    func analyzeFast(systemPrompt: String, userPrompt: String, enableCache: Bool = true) async -> String? {
        await analyze(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            priority: .normal,
            model: .mini,
            temperature: 0.1,
            jsonMode: false,
            enableCache: enableCache
        )
    }

    func analyzeCritical(systemPrompt: String, userPrompt: String) async -> String? {
        await analyze(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            priority: .critical,
            model: .standard,
            enableCache: false
        )
    }

    func getStats() -> AIAnalysisStats {
        var current = stats
        current.queuedRequests = requestQueue.count
        current.processingRequests = processingCount
        return current
    }

    func clearCache() {
        responseCache.removeAll()
        logger.log("AIAnalysisEngine: cache cleared (\(stats.cacheHits) hits, \(stats.cacheMisses) misses)", category: .automation, level: .info)
        stats.cacheHits = 0
        stats.cacheMisses = 0
    }

    func resetStats() {
        stats = AIAnalysisStats()
        logger.log("AIAnalysisEngine: stats reset", category: .automation, level: .info)
    }

    // MARK: - Private Implementation

    private func processRequest(_ request: AIAnalysisRequest) async -> String? {
        stats.totalRequests += 1

        // Check if we should queue or process immediately
        if processingCount >= maxConcurrentRequests {
            if requestQueue.count < maxQueueSize {
                requestQueue.append(request)
                requestQueue.sort { $0.priority < $1.priority }
                logger.log("AIAnalysisEngine: queued request \(request.id.uuidString.prefix(8)) (priority: \(request.priority), queue size: \(requestQueue.count))", category: .evaluation, level: .debug)

                // Wait for queue to process
                while requestQueue.contains(where: { $0.id == request.id }) {
                    try? await Task.sleep(for: .milliseconds(100))
                }

                // Check cache again after waiting (in case another request cached it)
                if let cacheKey = request.cacheKey, let cached = getCachedResponse(for: cacheKey) {
                    return cached.response
                }
            } else {
                logger.log("AIAnalysisEngine: queue full, rejecting request", category: .evaluation, level: .warning)
                stats.failedRequests += 1
                return nil
            }
        }

        return await executeRequest(request)
    }

    private func executeRequest(_ request: AIAnalysisRequest) async -> String? {
        processingCount += 1
        defer { processingCount -= 1 }

        let start = Date()

        let response = await grokService.generateText(
            systemPrompt: request.systemPrompt,
            userPrompt: request.userPrompt,
            model: request.model,
            jsonMode: request.jsonMode,
            temperature: request.temperature
        )

        let duration = Date().timeIntervalSince(start) * 1000 // ms

        if let response {
            // Update average response time
            let totalCompleted = Double(stats.completedRequests)
            stats.avgResponseTimeMs = (stats.avgResponseTimeMs * totalCompleted + duration) / (totalCompleted + 1)
            stats.completedRequests += 1

            // Cache the response if cache key provided
            if let cacheKey = request.cacheKey {
                cacheResponse(response, for: cacheKey)
            }

            logger.log("AIAnalysisEngine: completed request in \(Int(duration))ms (model: \(request.model.rawValue))", category: .evaluation, level: .debug)

            // Process next queued request if any
            Task {
                await processNextQueuedRequest()
            }

            return response
        } else {
            stats.failedRequests += 1
            logger.log("AIAnalysisEngine: request failed after \(Int(duration))ms", category: .evaluation, level: .warning)

            // Process next queued request even on failure
            Task {
                await processNextQueuedRequest()
            }

            return nil
        }
    }

    private func processNextQueuedRequest() async {
        guard !requestQueue.isEmpty, processingCount < maxConcurrentRequests else { return }

        let request = requestQueue.removeFirst()
        logger.log("AIAnalysisEngine: processing queued request \(request.id.uuidString.prefix(8)) (waited \(Int(Date().timeIntervalSince(request.timestamp) * 1000))ms)", category: .evaluation, level: .debug)

        _ = await executeRequest(request)
    }

    private func generateCacheKey(systemPrompt: String, userPrompt: String, model: GrokModel) -> String {
        let combined = "\(model.rawValue)|\(systemPrompt)|\(userPrompt)"
        return String(combined.hashValue)
    }

    private func getCachedResponse(for key: String) -> CachedResponse? {
        // Clean expired entries first
        let now = Date()
        responseCache = responseCache.filter { $0.value.expiresAt > now }

        guard let cached = responseCache[key] else { return nil }
        guard cached.expiresAt > now else {
            responseCache.removeValue(forKey: key)
            return nil
        }

        return cached
    }

    private func cacheResponse(_ response: String, for key: String) {
        let now = Date()
        let cached = CachedResponse(
            response: response,
            cachedAt: now,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        responseCache[key] = cached

        // Limit cache size
        if responseCache.count > 200 {
            let sorted = responseCache.sorted { $0.value.expiresAt < $1.value.expiresAt }
            for (key, _) in sorted.prefix(50) {
                responseCache.removeValue(forKey: key)
            }
        }
    }
}
