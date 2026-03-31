import Foundation

// MARK: - Classification Type

nonisolated enum ClassificationType: String, CaseIterable, Sendable {
    case loginSuccess
    case pageBlocked
    case captchaDetected
    case errorPage
    case loadingComplete
    case formReady
}

// MARK: - Classification Query

nonisolated struct ClassificationQuery: Sendable {
    let input: String
    let context: String?
    let queryType: ClassificationType

    init(input: String, context: String? = nil, queryType: ClassificationType) {
        self.input = input
        self.context = context
        self.queryType = queryType
    }
}

// MARK: - Classification Result

nonisolated struct ClassificationResult: Sendable {
    let classification: Bool
    let confidence: Double
    let reasoning: String
    let latencyMs: Int
    let usedOnDevice: Bool

    static let empty = ClassificationResult(
        classification: false,
        confidence: 0.0,
        reasoning: "No classification performed",
        latencyMs: 0,
        usedOnDevice: false
    )
}

// MARK: - On-Device Intelligence Service

@Observable
@MainActor
final class OnDeviceIntelligenceService {
    static let shared = OnDeviceIntelligenceService()

    private let logger = DebugLogger.shared
    private let analysisEngine = AIAnalysisEngine.shared

    // MARK: - Statistics

    private(set) var onDeviceClassificationCount: Int = 0
    private(set) var fallbackClassificationCount: Int = 0

    private var totalOnDeviceLatencyMs: Int = 0
    private var totalFallbackLatencyMs: Int = 0

    var averageOnDeviceLatencyMs: Double {
        guard onDeviceClassificationCount > 0 else { return 0.0 }
        return Double(totalOnDeviceLatencyMs) / Double(onDeviceClassificationCount)
    }

    var averageFallbackLatencyMs: Double {
        guard fallbackClassificationCount > 0 else { return 0.0 }
        return Double(totalFallbackLatencyMs) / Double(fallbackClassificationCount)
    }

    // MARK: - Availability

    var isOnDeviceAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    // MARK: - Init

    private init() {
        logger.log(
            "OnDeviceIntelligenceService initialized",
            category: .ai,
            level: .info,
            detail: "On-device available: \(isOnDeviceAvailable)"
        )
    }

    // MARK: - Classification

    func classify(_ query: ClassificationQuery) async -> ClassificationResult {
        let start = DispatchTime.now()

        let result: ClassificationResult

        if #available(iOS 26.0, *) {
            result = await classifyOnDevice(query, start: start)
        } else {
            result = await classifyWithFallback(query, start: start)
        }

        logger.log(
            "\(result.usedOnDevice ? "On-device" : "Fallback") classification complete",
            category: .ai,
            level: .success,
            detail: "type=\(query.queryType.rawValue) result=\(result.classification) confidence=\(String(format: "%.2f", result.confidence)) latency=\(result.latencyMs)ms"
        )

        return result
    }

    // MARK: - On-Device Path (iOS 26+)

    @available(iOS 26.0, *)
    private func classifyOnDevice(_ query: ClassificationQuery, start: DispatchTime) -> ClassificationResult {
        // Foundation Models framework stub: when Apple Intelligence SDK ships,
        // replace this body with a FoundationModels.LanguageModelSession call
        // performing binary classification on the query input.
        let classification = evaluateHeuristic(query)
        let latencyMs = millisecondsSince(start)

        onDeviceClassificationCount += 1
        totalOnDeviceLatencyMs += latencyMs

        return ClassificationResult(
            classification: classification.value,
            confidence: classification.confidence,
            reasoning: classification.reasoning,
            latencyMs: latencyMs,
            usedOnDevice: true
        )
    }

    // MARK: - Fallback Path

    private func classifyWithFallback(_ query: ClassificationQuery, start: DispatchTime) async -> ClassificationResult {
        let systemPrompt = "You are a binary classifier. Respond with ONLY 'true' or 'false'. Classify whether the following page content indicates: \(query.queryType.rawValue)."
        let userPrompt = "Page content: \(query.input)\(query.context.map { "\nContext: \($0)" } ?? "")"

        let response = await analysisEngine.analyze(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            priority: .critical,
            temperature: 0.1,
            enableCache: true
        )
        let latencyMs = millisecondsSince(start)

        let classification = parseClassificationResponse(response)

        fallbackClassificationCount += 1
        totalFallbackLatencyMs += latencyMs

        return ClassificationResult(
            classification: classification.value,
            confidence: classification.confidence,
            reasoning: classification.reasoning,
            latencyMs: latencyMs,
            usedOnDevice: false
        )
    }

    // MARK: - Heuristic Evaluation

    private func evaluateHeuristic(_ query: ClassificationQuery) -> (value: Bool, confidence: Double, reasoning: String) {
        let lowered = query.input.lowercased()
        let contextLowered = (query.context ?? "").lowercased()

        switch query.queryType {
        case .loginSuccess:
            let successSignals = ["welcome", "dashboard", "account", "logged in", "my profile"]
            let matched = successSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let detected = !matched.isEmpty
            let confidence = detected ? min(0.6 + Double(matched.count) * 0.1, 0.95) : 0.3
            return (detected, confidence, "Heuristic: \(matched.count) success signal(s) found")

        case .pageBlocked:
            let blockSignals = ["blocked", "denied", "403", "forbidden", "access denied", "cloudflare"]
            let matched = blockSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let detected = !matched.isEmpty
            let confidence = detected ? min(0.65 + Double(matched.count) * 0.1, 0.95) : 0.25
            return (detected, confidence, "Heuristic: \(matched.count) block signal(s) found")

        case .captchaDetected:
            let captchaSignals = ["captcha", "recaptcha", "hcaptcha", "verify you are human", "robot"]
            let matched = captchaSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let detected = !matched.isEmpty
            let confidence = detected ? min(0.7 + Double(matched.count) * 0.1, 0.95) : 0.2
            return (detected, confidence, "Heuristic: \(matched.count) captcha signal(s) found")

        case .errorPage:
            let errorSignals = ["error", "500", "404", "not found", "something went wrong", "oops"]
            let matched = errorSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let detected = !matched.isEmpty
            let confidence = detected ? min(0.6 + Double(matched.count) * 0.1, 0.95) : 0.3
            return (detected, confidence, "Heuristic: \(matched.count) error signal(s) found")

        case .loadingComplete:
            let loadingSignals = ["loading", "spinner", "please wait", "processing"]
            let matched = loadingSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let stillLoading = !matched.isEmpty
            let confidence = stillLoading ? 0.5 : 0.7
            return (!stillLoading, confidence, "Heuristic: \(matched.count) loading indicator(s) \(stillLoading ? "present" : "absent")")

        case .formReady:
            let formSignals = ["input", "password", "email", "username", "submit", "sign in", "log in"]
            let matched = formSignals.filter { lowered.contains($0) || contextLowered.contains($0) }
            let detected = matched.count >= 2
            let confidence = detected ? min(0.6 + Double(matched.count) * 0.08, 0.95) : 0.35
            return (detected, confidence, "Heuristic: \(matched.count) form signal(s) found")
        }
    }

    // MARK: - Response Parsing

    private func parseClassificationResponse(_ response: String?) -> (value: Bool, confidence: Double, reasoning: String) {
        guard let response else {
            return (false, 0.1, "AI engine returned no response")
        }

        let resultLowered = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let positiveIndicators = ["true", "yes", "detected", "confirmed", "success", "1"]
        let isPositive = positiveIndicators.contains(where: { resultLowered.contains($0) })

        let confidence: Double = isPositive ? 0.75 : 0.7
        let reasoning = "AI engine classification: \(resultLowered.prefix(50))"

        return (isPositive, confidence, reasoning)
    }

    // MARK: - Statistics

    func resetStatistics() {
        onDeviceClassificationCount = 0
        fallbackClassificationCount = 0
        totalOnDeviceLatencyMs = 0
        totalFallbackLatencyMs = 0

        logger.log(
            "Intelligence statistics reset",
            category: .ai,
            level: .info
        )
    }

    var diagnosticSummary: String {
        let totalCount = onDeviceClassificationCount + fallbackClassificationCount
        let onDevicePercent = totalCount > 0
            ? String(format: "%.1f", Double(onDeviceClassificationCount) / Double(totalCount) * 100)
            : "0.0"

        return """
        OnDeviceIntelligenceService:
          Available: \(isOnDeviceAvailable)
          Total classifications: \(totalCount)
          On-device: \(onDeviceClassificationCount) (\(onDevicePercent)%)
          Fallback: \(fallbackClassificationCount)
          Avg on-device latency: \(String(format: "%.1f", averageOnDeviceLatencyMs))ms
          Avg fallback latency: \(String(format: "%.1f", averageFallbackLatencyMs))ms
        """
    }

    // MARK: - Helpers

    private func millisecondsSince(_ start: DispatchTime) -> Int {
        let end = DispatchTime.now()
        let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }
}
