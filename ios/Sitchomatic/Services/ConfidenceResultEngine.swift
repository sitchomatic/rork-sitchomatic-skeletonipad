import Foundation
import UIKit

@MainActor
class ConfidenceResultEngine {
    static let shared = ConfidenceResultEngine()

    private let logger = DebugLogger.shared
    private let vision = UnifiedAIVisionService.shared

    nonisolated struct ConfidenceResult: Sendable {
        let outcome: LoginOutcome
        let confidence: Double
        let compositeScore: Double
        let signalBreakdown: [SignalContribution]
        let reasoning: String
    }

    nonisolated struct SignalContribution: Sendable {
        let source: String
        let weight: Double
        let rawScore: Double
        let weightedScore: Double
        let detail: String
    }

    func evaluate(
        pageContent: String,
        currentURL: String,
        preLoginURL: String,
        pageTitle: String,
        welcomeTextFound: Bool,
        redirectedToHomepage: Bool,
        navigationDetected: Bool,
        contentChanged: Bool,
        responseTimeMs: Int,
        screenshot: UIImage? = nil,
        httpStatus: Int? = nil
    ) async -> ConfidenceResult {
        if let screenshot {
            let context = VisionContext(site: .joe, phase: .login, currentURL: currentURL)
            let result = await vision.analyzeScreenshot(screenshot, context: context)

            let confidence = Double(result.confidence) / 100.0
            let signal = SignalContribution(
                source: "AI_VISION",
                weight: 1.0,
                rawScore: confidence,
                weightedScore: confidence,
                detail: "AI Vision: \(result.reasoning)"
            )

            logger.log("ConfidenceEngine: AI Vision → \(result.outcome) conf=\(result.confidence)% — \(result.reasoning)", category: .evaluation, level: result.outcome == .success ? .success : .info)

            return ConfidenceResult(
                outcome: result.outcome,
                confidence: confidence,
                compositeScore: confidence,
                signalBreakdown: [signal],
                reasoning: result.reasoning
            )
        }

        let confidence = 0.3
        return ConfidenceResult(
            outcome: .unsure,
            confidence: confidence,
            compositeScore: confidence,
            signalBreakdown: [SignalContribution(source: "NO_SCREENSHOT", weight: 1.0, rawScore: 0.3, weightedScore: 0.3, detail: "No screenshot available for AI Vision")],
            reasoning: "No screenshot available — unsure"
        )
    }

    func recordOutcomeFeedback(host: String, predictedOutcome: LoginOutcome, actualOutcome: LoginOutcome, confidence: Double, pageContent: String) {
    }
}
