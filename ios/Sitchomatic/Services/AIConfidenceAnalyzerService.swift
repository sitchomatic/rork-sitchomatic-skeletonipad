import Foundation

nonisolated struct HostKeywordProfile: Codable, Sendable {
    var successKeywords: [String: Int] = [:]
    var failKeywords: [String: Int] = [:]
    var disabledKeywords: [String: Int] = [:]
    var tempDisabledKeywords: [String: Int] = [:]
    var totalFeedback: Int = 0
    var lastUpdated: Date = .distantPast
}

nonisolated struct AIClassificationResult: Codable, Sendable {
    let outcome: String
    let confidence: Double
    let reasoning: String
    let newKeywords: [String]?
}

nonisolated struct ConfidenceFeedbackRecord: Codable, Sendable {
    let host: String
    let predictedOutcome: String
    let actualOutcome: String
    let confidence: Double
    let pageSnippet: String
    let timestamp: Date
}

nonisolated struct AIConfidenceStore: Codable, Sendable {
    var hostProfiles: [String: HostKeywordProfile] = [:]
    var feedbackHistory: [ConfidenceFeedbackRecord] = []
    var aiCallCount: Int = 0
    var aiCorrections: Int = 0
}

@MainActor
class AIConfidenceAnalyzerService {
    static let shared = AIConfidenceAnalyzerService()

    func shouldUseAIFallback(confidence: Double) -> Bool {
        false
    }

    func analyzeWithAI(
        host: String,
        pageContent: String,
        currentURL: String,
        pageTitle: String,
        staticOutcome: String,
        staticConfidence: Double
    ) async -> AIClassificationResult? {
        nil
    }

    func learnedKeywordBoost(host: String, pageContent: String) -> (outcome: String, boost: Double)? {
        nil
    }

    func recordFeedback(
        host: String,
        predictedOutcome: String,
        actualOutcome: String,
        confidence: Double,
        pageContent: String,
        newKeywords: [String]? = nil
    ) {
    }
}
