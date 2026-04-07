import Foundation
import UIKit

@MainActor
class StrictLoginDetectionEngine {
    static let shared = StrictLoginDetectionEngine()

    private let logger = DebugLogger.shared
    private let vision = UnifiedAIVisionService.shared
    private let coordEngine = CoordinateInteractionEngine.shared

    nonisolated enum DetectionModule: Sendable {
        case standard
        case dualFind
        case unifiedSession
    }

    nonisolated struct DetectionContext: Sendable {
        let module: DetectionModule
        let sessionId: String
        let pageContent: String
        let currentURL: String
        let preLoginURL: String
        let screenshot: UIImage?
    }

    nonisolated struct DetectionResult: Sendable {
        let outcome: LoginOutcome
        let phase: String
        let reason: String
        let incorrectDetectedViaDOM: Bool
        let incorrectDetectedViaOCR: Bool
        let buttonCycleCompleted: Bool
        let retryPerformed: Bool
        let detectedIncorrect: Bool
    }

    func evaluateImmediateOverrides(
        pageContent: String,
        screenshot: UIImage?,
        sessionId: String
    ) async -> LoginOutcome? {
        guard let img = screenshot else { return nil }

        let context = VisionContext(site: .joe, phase: .login, sessionId: sessionId)
        let result = await vision.analyzeScreenshot(img, context: context)

        if result.confidence >= 60 && result.outcome != .unsure {
            logger.log("StrictDetection P1: AI Vision → \(result.outcome) conf=\(result.confidence)% — \(result.reasoning)", category: .evaluation, level: result.outcome == .success ? .success : .critical, sessionId: sessionId)
            return result.outcome
        }

        return nil
    }

    func evaluatePostSubmit(
        session: LoginSiteWebSession,
        sessionId: String,
        buttonCycleCompleted: Bool
    ) async -> DetectionResult {
        try? await Task.sleep(for: .seconds(2))

        guard let screenshot = await session.captureScreenshot() else {
            return DetectionResult(outcome: .unsure, phase: "AI_Vision", reason: "Screenshot capture failed", incorrectDetectedViaDOM: false, incorrectDetectedViaOCR: false, buttonCycleCompleted: buttonCycleCompleted, retryPerformed: false, detectedIncorrect: false)
        }

        let context = VisionContext(site: .joe, phase: .login, currentURL: session.targetURL.absoluteString, sessionId: sessionId)
        let result = await vision.analyzeScreenshot(screenshot, context: context)

        let isIncorrect = result.outcome == .noAcc
        logger.log("StrictDetection: AI Vision → \(result.outcome) conf=\(result.confidence)% — \(result.reasoning)", category: .evaluation, level: result.outcome == .success ? .success : .info, sessionId: sessionId)

        return DetectionResult(
            outcome: result.outcome,
            phase: "AI_Vision",
            reason: result.reasoning,
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: isIncorrect,
            buttonCycleCompleted: buttonCycleCompleted,
            retryPerformed: false,
            detectedIncorrect: isIncorrect
        )
    }

    func evaluateStrict(
        session: LoginSiteWebSession,
        module: DetectionModule,
        sessionId: String
    ) async -> DetectionResult {
        try? await Task.sleep(for: .seconds(2))

        guard let screenshot = await session.captureScreenshot() else {
            return DetectionResult(outcome: .unsure, phase: "AI_Vision", reason: "Screenshot capture failed", incorrectDetectedViaDOM: false, incorrectDetectedViaOCR: false, buttonCycleCompleted: true, retryPerformed: false, detectedIncorrect: false)
        }

        let context = VisionContext(site: .joe, phase: .login, currentURL: session.targetURL.absoluteString, sessionId: sessionId)
        let result = await vision.analyzeScreenshot(screenshot, context: context)

        let isIncorrect = result.outcome == .noAcc
        logger.log("StrictDetection evaluateStrict: AI Vision → \(result.outcome) conf=\(result.confidence)% — \(result.reasoning)", category: .evaluation, level: result.outcome == .success ? .success : .info, sessionId: sessionId)

        return DetectionResult(
            outcome: result.outcome,
            phase: "AI_Vision",
            reason: result.reasoning,
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: isIncorrect,
            buttonCycleCompleted: true,
            retryPerformed: false,
            detectedIncorrect: isIncorrect
        )
    }

    func runStandardLoginDetection(
        session: LoginSiteWebSession,
        submitSelectors: [String],
        fallbackSelectors: [String],
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)? = nil
    ) async -> DetectionResult {
        let executeJS: (String) async -> String? = { js in await session.executeJS(js) }

        onLog?("StrictDetection: triple-click submit via AI Vision pipeline", .info)
        let tripleResult = await coordEngine.tripleClickWithEscalatingDwell(
            selectors: submitSelectors,
            fallbackSelectors: fallbackSelectors,
            executeJS: executeJS,
            jitterPx: 3,
            sessionId: sessionId
        )
        onLog?("StrictDetection: triple-click \(tripleResult.success ? "OK" : "PARTIAL") (\(tripleResult.clicksCompleted)/3)", tripleResult.success ? .success : .warning)

        let settlementContext = VisionContext(site: .joe, phase: .settlement, currentURL: session.targetURL.absoluteString, sessionId: sessionId)
        let settlement = await AIVisionSettlementService.shared.waitForSettlement(
            captureScreenshot: { await session.captureScreenshot() },
            context: settlementContext
        )

        let result = settlement.outcome
        let isIncorrect = result.outcome == .noAcc
        onLog?("StrictDetection: AI Vision settled in \(settlement.durationMs)ms → \(result.outcome) conf=\(result.confidence)% — \(result.reasoning)", result.outcome == .success ? .success : result.outcome == .unsure ? .warning : .info)

        return DetectionResult(
            outcome: result.outcome,
            phase: "AI_Vision_Settlement",
            reason: result.reasoning,
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: isIncorrect,
            buttonCycleCompleted: settlement.settled,
            retryPerformed: false,
            detectedIncorrect: isIncorrect
        )
    }

    nonisolated static func categorizeByIncorrectCount(_ completedIncorrectCycles: Int) -> LoginOutcome {
        switch completedIncorrectCycles {
        case 0: return .unsure
        case 1, 2: return .noAcc
        case 3...: return .noAcc
        default: return .unsure
        }
    }

    nonisolated static func incorrectCountLabel(_ completedIncorrectCycles: Int) -> String {
        switch completedIncorrectCycles {
        case 0: return "unchecked"
        case 1: return "1incorrect"
        case 2: return "2incorrect"
        case 3...: return "noAcc_final"
        default: return "unknown"
        }
    }

    nonisolated static func shouldRequeue(_ completedIncorrectCycles: Int) -> Bool {
        completedIncorrectCycles > 0 && completedIncorrectCycles < 3
    }

    nonisolated static func isFinalNoAccount(_ completedIncorrectCycles: Int) -> Bool {
        completedIncorrectCycles >= 3
    }
}
