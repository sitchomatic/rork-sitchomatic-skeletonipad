import Foundation
import UIKit

@MainActor
class StrictLoginDetectionEngine {
    static let shared = StrictLoginDetectionEngine()

    private let logger = DebugLogger.shared
    private let visionOCR = VisionTextCropService.shared
    private let grokService = RorkToolkitService.shared
    private let settlementGate = SettlementGateEngine.shared
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

    // MARK: - Phase 1: Immediate Overrides

    func evaluateImmediateOverrides(
        pageContent: String,
        screenshot: UIImage?,
        sessionId: String
    ) async -> LoginOutcome? {
        let contentLower = pageContent.lowercased()

        if contentLower.contains("has been disabled") {
            logger.log("StrictDetection P1: PERM_DISABLED — 'has been disabled' in DOM", category: .evaluation, level: .critical, sessionId: sessionId)
            return .permDisabled
        }

        if contentLower.contains("temporarily disabled") {
            logger.log("StrictDetection P1: TEMP_DISABLED — 'temporarily disabled' in DOM", category: .evaluation, level: .critical, sessionId: sessionId)
            return .tempDisabled
        }

        let domHasSuccess = contentLower.contains("recommended for you") || contentLower.contains("last played")

        var ocrHasSuccess = false
        if let img = screenshot {
            let ocrResult = await visionOCR.analyzeScreenshot(img)
            let ocrLower = ocrResult.allText.lowercased()
            ocrHasSuccess = ocrLower.contains("recommended for you") || ocrLower.contains("last played")

            if !domHasSuccess && !ocrHasSuccess {
                if ocrLower.contains("has been disabled") {
                    logger.log("StrictDetection P1: PERM_DISABLED — 'has been disabled' via OCR", category: .evaluation, level: .critical, sessionId: sessionId)
                    return .permDisabled
                }
                if ocrLower.contains("temporarily disabled") {
                    logger.log("StrictDetection P1: TEMP_DISABLED — 'temporarily disabled' via OCR", category: .evaluation, level: .critical, sessionId: sessionId)
                    return .tempDisabled
                }
            }
        }

        if domHasSuccess || ocrHasSuccess {
            let source = domHasSuccess ? "DOM" : "OCR"
            logger.log("StrictDetection P1: SUCCESS — lobby markers detected via \(source)", category: .evaluation, level: .success, sessionId: sessionId)
            return .success
        }

        return nil
    }

    // MARK: - Phase 3+4+5: Post-Submit Evaluation

    func evaluatePostSubmit(
        session: LoginSiteWebSession,
        sessionId: String,
        buttonCycleCompleted: Bool
    ) async -> DetectionResult {
        let pageContent = (await session.getPageContent() ?? "").lowercased()

        let p1Override = await evaluateImmediateOverrides(
            pageContent: pageContent,
            screenshot: await session.captureScreenshot(),
            sessionId: sessionId
        )
        if let override = p1Override {
            return DetectionResult(
                outcome: override,
                phase: "P1_override",
                reason: "Immediate override detected post-submit",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: false,
                detectedIncorrect: false
            )
        }

        try? await Task.sleep(for: .milliseconds(3500))

        let settledContent = (await session.getPageContent() ?? "").lowercased()

        if settledContent.contains("incorrect") {
            logger.log("StrictDetection P3: 'incorrect' found in DOM after 3.5s wait", category: .evaluation, level: .info, sessionId: sessionId)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P3_DOM",
                reason: "DOM scan found 'incorrect' after button cycle + 3.5s settle",
                incorrectDetectedViaDOM: true,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: false,
                detectedIncorrect: true
            )
        }

        let ocrFoundIncorrect = await ocrScanForIncorrect(session: session, sessionId: sessionId)
        if ocrFoundIncorrect {
            logger.log("StrictDetection P4-Step7: 'incorrect' found via OCR verification", category: .evaluation, level: .info, sessionId: sessionId)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_OCR",
                reason: "OCR verification (Vision+Grok fallback) found 'incorrect'",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: true,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: false,
                detectedIncorrect: true
            )
        }

        logger.log("StrictDetection P4-Step8: first cycle inconclusive — starting ONE full retry", category: .evaluation, level: .warning, sessionId: sessionId)

        let retryP1Override = await evaluateImmediateOverrides(
            pageContent: (await session.getPageContent() ?? "").lowercased(),
            screenshot: await session.captureScreenshot(),
            sessionId: sessionId
        )
        if let override = retryP1Override {
            return DetectionResult(
                outcome: override,
                phase: "P1_override_retry",
                reason: "Immediate override detected on retry cycle",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: true,
                detectedIncorrect: false
            )
        }

        try? await Task.sleep(for: .milliseconds(3500))

        let retryContent = (await session.getPageContent() ?? "").lowercased()

        if retryContent.contains("incorrect") {
            logger.log("StrictDetection P4-Step8: 'incorrect' found in DOM on retry cycle", category: .evaluation, level: .info, sessionId: sessionId)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_DOM_retry",
                reason: "DOM scan found 'incorrect' on retry cycle after second 3.5s settle",
                incorrectDetectedViaDOM: true,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: true,
                detectedIncorrect: true
            )
        }

        let retryOCR = await ocrScanForIncorrect(session: session, sessionId: sessionId)
        if retryOCR {
            logger.log("StrictDetection P4-Step8: 'incorrect' found via OCR on retry cycle", category: .evaluation, level: .info, sessionId: sessionId)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_OCR_retry",
                reason: "OCR found 'incorrect' on retry cycle",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: true,
                buttonCycleCompleted: buttonCycleCompleted,
                retryPerformed: true,
                detectedIncorrect: true
            )
        }

        logger.log("StrictDetection P4-Step9: No 'incorrect' detected after full first attempt + retry — unsure", category: .evaluation, level: .warning, sessionId: sessionId)
        return DetectionResult(
            outcome: .unsure,
            phase: "P4_final",
            reason: "Neither DOM nor OCR detected 'incorrect' after complete first attempt + full retry — extremely rare unsure",
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: false,
            buttonCycleCompleted: buttonCycleCompleted,
            retryPerformed: true,
            detectedIncorrect: false
        )
    }

    // MARK: - Full Strict Evaluation (for modules that handle their own submit)

    func evaluateStrict(
        session: LoginSiteWebSession,
        module: DetectionModule,
        sessionId: String
    ) async -> DetectionResult {
        let pageContent = (await session.getPageContent() ?? "").lowercased()
        let screenshot = await session.captureScreenshot()

        let p1Override = await evaluateImmediateOverrides(
            pageContent: pageContent,
            screenshot: screenshot,
            sessionId: sessionId
        )
        if let override = p1Override {
            return DetectionResult(
                outcome: override,
                phase: "P1",
                reason: "Phase 1 immediate override",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: false,
                retryPerformed: false,
                detectedIncorrect: false
            )
        }

        if pageContent.contains("incorrect") {
            logger.log("StrictDetection: 'incorrect' found in DOM (post-submit eval)", category: .evaluation, level: .info, sessionId: sessionId)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P3_DOM",
                reason: "DOM contains 'incorrect'",
                incorrectDetectedViaDOM: true,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: true,
                retryPerformed: false,
                detectedIncorrect: true
            )
        }

        let ocrFoundIncorrect = await ocrScanForIncorrect(session: session, sessionId: sessionId)
        if ocrFoundIncorrect {
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_OCR",
                reason: "OCR found 'incorrect'",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: true,
                buttonCycleCompleted: true,
                retryPerformed: false,
                detectedIncorrect: true
            )
        }

        return DetectionResult(
            outcome: .unsure,
            phase: "P4_final",
            reason: "No 'incorrect' detected via DOM or OCR — unsure",
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: false,
            buttonCycleCompleted: true,
            retryPerformed: false,
            detectedIncorrect: false
        )
    }

    // MARK: - Full Pipeline for Standard Login (Phase 3 + 4 with retry)

    func runStandardLoginDetection(
        session: LoginSiteWebSession,
        submitSelectors: [String],
        fallbackSelectors: [String],
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)? = nil
    ) async -> DetectionResult {
        let preContent = (await session.getPageContent() ?? "").lowercased()
        let preScreenshot = await session.captureScreenshot()

        let p1Override = await evaluateImmediateOverrides(
            pageContent: preContent,
            screenshot: preScreenshot,
            sessionId: sessionId
        )
        if let override = p1Override {
            onLog?("StrictDetection P1: immediate override → \(override)", override == .success ? .success : .error)
            return DetectionResult(
                outcome: override,
                phase: "P1",
                reason: "Phase 1 immediate override before submit",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: false,
                buttonCycleCompleted: false,
                retryPerformed: false,
                detectedIncorrect: false
            )
        }

        let executeJS: (String) async -> String? = { js in await session.executeJS(js) }

        let preClickFingerprint = await settlementGate.capturePreClickFingerprint(
            executeJS: executeJS,
            sessionId: sessionId
        )

        onLog?("StrictDetection P3: triple-click submit", .info)
        let tripleResult = await coordEngine.tripleClickWithEscalatingDwell(
            selectors: submitSelectors,
            fallbackSelectors: fallbackSelectors,
            executeJS: executeJS,
            jitterPx: 3,
            sessionId: sessionId
        )
        onLog?("StrictDetection P3: triple-click \(tripleResult.success ? "OK" : "PARTIAL") (\(tripleResult.clicksCompleted)/3)", tripleResult.success ? .success : .warning)

        var buttonCycleOk = false
        if let fingerprint = preClickFingerprint {
            let settlement = await settlementGate.waitForSettlement(
                originalFingerprint: fingerprint,
                executeJS: executeJS,
                maxTimeoutMs: 15000,
                preClickURL: session.targetURL.absoluteString,
                sessionId: sessionId
            )
            buttonCycleOk = settlement.sawLoadingState
            onLog?("StrictDetection P3: button cycle \(settlement.sawLoadingState ? "COMPLETED" : "no loading detected") (\(settlement.durationMs)ms) — \(settlement.reason)", settlement.sawLoadingState ? .success : .warning)
        } else {
            try? await Task.sleep(for: .seconds(4))
            buttonCycleOk = true
            onLog?("StrictDetection P3: no fingerprint captured — used fixed 4s delay", .warning)
        }

        let firstAttemptResult = await evaluatePostSubmitDOM(session: session, sessionId: sessionId, label: "P3")
        if let result = firstAttemptResult {
            return DetectionResult(
                outcome: result.outcome,
                phase: result.phase,
                reason: result.reason,
                incorrectDetectedViaDOM: result.incorrectDetectedViaDOM,
                incorrectDetectedViaOCR: result.incorrectDetectedViaOCR,
                buttonCycleCompleted: buttonCycleOk,
                retryPerformed: false,
                detectedIncorrect: result.incorrectDetectedViaDOM || result.incorrectDetectedViaOCR
            )
        }

        onLog?("StrictDetection P4-Step7: DOM didn't find 'incorrect' — running OCR verification", .info)
        let ocrFound = await ocrScanForIncorrect(session: session, sessionId: sessionId)
        if ocrFound {
            onLog?("StrictDetection P4-Step7: OCR found 'incorrect'", .info)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_OCR_first",
                reason: "OCR verification found 'incorrect' on first attempt",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: true,
                buttonCycleCompleted: buttonCycleOk,
                retryPerformed: false,
                detectedIncorrect: true
            )
        }

        onLog?("StrictDetection P4-Step8: starting ONE full retry cycle", .warning)

        let retryFingerprint = await settlementGate.capturePreClickFingerprint(
            executeJS: executeJS,
            sessionId: sessionId
        )

        let retryTriple = await coordEngine.tripleClickWithEscalatingDwell(
            selectors: submitSelectors,
            fallbackSelectors: fallbackSelectors,
            executeJS: executeJS,
            jitterPx: 3,
            sessionId: sessionId
        )
        onLog?("StrictDetection P4-Step8: retry triple-click \(retryTriple.success ? "OK" : "PARTIAL")", retryTriple.success ? .info : .warning)

        if let fp = retryFingerprint {
            let retrySettlement = await settlementGate.waitForSettlement(
                originalFingerprint: fp,
                executeJS: executeJS,
                maxTimeoutMs: 15000,
                preClickURL: session.targetURL.absoluteString,
                sessionId: sessionId
            )
            onLog?("StrictDetection P4-Step8: retry button cycle \(retrySettlement.sawLoadingState ? "COMPLETED" : "no loading") (\(retrySettlement.durationMs)ms)", retrySettlement.sawLoadingState ? .info : .warning)
        } else {
            try? await Task.sleep(for: .seconds(4))
        }

        let retryDOMResult = await evaluatePostSubmitDOM(session: session, sessionId: sessionId, label: "P4-retry")
        if let result = retryDOMResult {
            return DetectionResult(
                outcome: result.outcome,
                phase: result.phase,
                reason: result.reason + " (retry cycle)",
                incorrectDetectedViaDOM: result.incorrectDetectedViaDOM,
                incorrectDetectedViaOCR: result.incorrectDetectedViaOCR,
                buttonCycleCompleted: true,
                retryPerformed: true,
                detectedIncorrect: result.incorrectDetectedViaDOM || result.incorrectDetectedViaOCR
            )
        }

        let retryOCR = await ocrScanForIncorrect(session: session, sessionId: sessionId)
        if retryOCR {
            onLog?("StrictDetection P4-Step8: retry OCR found 'incorrect'", .info)
            return DetectionResult(
                outcome: .noAcc,
                phase: "P4_OCR_retry",
                reason: "OCR found 'incorrect' on retry cycle",
                incorrectDetectedViaDOM: false,
                incorrectDetectedViaOCR: true,
                buttonCycleCompleted: true,
                retryPerformed: true,
                detectedIncorrect: true
            )
        }

        onLog?("StrictDetection P4-Step9: UNSURE — neither DOM nor OCR found 'incorrect' after full retry", .error)
        return DetectionResult(
            outcome: .unsure,
            phase: "P4_final_unsure",
            reason: "Complete first attempt + full retry: no 'incorrect' detected anywhere — extremely rare unsure",
            incorrectDetectedViaDOM: false,
            incorrectDetectedViaOCR: false,
            buttonCycleCompleted: true,
            retryPerformed: true,
            detectedIncorrect: false
        )
    }

    // MARK: - Phase 5: Categorize by incorrect count

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

    // MARK: - Private Helpers

    private struct PartialResult {
        let outcome: LoginOutcome
        let phase: String
        let reason: String
        let incorrectDetectedViaDOM: Bool
        let incorrectDetectedViaOCR: Bool
    }

    private func evaluatePostSubmitDOM(
        session: LoginSiteWebSession,
        sessionId: String,
        label: String
    ) async -> PartialResult? {
        try? await Task.sleep(for: .milliseconds(3500))

        let content = (await session.getPageContent() ?? "").lowercased()

        if content.contains("has been disabled") {
            logger.log("StrictDetection \(label): PERM_DISABLED in DOM after settle", category: .evaluation, level: .critical, sessionId: sessionId)
            return PartialResult(outcome: .permDisabled, phase: "\(label)_DOM", reason: "'has been disabled' in DOM", incorrectDetectedViaDOM: false, incorrectDetectedViaOCR: false)
        }

        if content.contains("temporarily disabled") {
            logger.log("StrictDetection \(label): TEMP_DISABLED in DOM after settle", category: .evaluation, level: .critical, sessionId: sessionId)
            return PartialResult(outcome: .tempDisabled, phase: "\(label)_DOM", reason: "'temporarily disabled' in DOM", incorrectDetectedViaDOM: false, incorrectDetectedViaOCR: false)
        }

        if content.contains("recommended for you") || content.contains("last played") {
            logger.log("StrictDetection \(label): SUCCESS — lobby markers in DOM", category: .evaluation, level: .success, sessionId: sessionId)
            return PartialResult(outcome: .success, phase: "\(label)_DOM", reason: "Lobby markers in DOM post-submit", incorrectDetectedViaDOM: false, incorrectDetectedViaOCR: false)
        }

        if content.contains("incorrect") {
            logger.log("StrictDetection \(label): 'incorrect' found in DOM", category: .evaluation, level: .info, sessionId: sessionId)
            return PartialResult(outcome: .noAcc, phase: "\(label)_DOM", reason: "'incorrect' in DOM after 3.5s settle", incorrectDetectedViaDOM: true, incorrectDetectedViaOCR: false)
        }

        return nil
    }

    private func ocrScanForIncorrect(session: LoginSiteWebSession, sessionId: String) async -> Bool {
        guard let screenshot = await session.captureScreenshot() else {
            logger.log("StrictDetection OCR: screenshot capture failed", category: .evaluation, level: .warning, sessionId: sessionId)
            return false
        }

        let ocrResult = await visionOCR.analyzeScreenshot(screenshot)
        let ocrLower = ocrResult.allText.lowercased()

        if ocrLower.contains("incorrect") {
            logger.log("StrictDetection OCR: 'incorrect' found via on-device Vision OCR", category: .evaluation, level: .info, sessionId: sessionId)
            return true
        }

        if ocrLower.contains("has been disabled") || ocrLower.contains("temporarily disabled") ||
           ocrLower.contains("recommended for you") || ocrLower.contains("last played") {
            logger.log("StrictDetection OCR: override keyword found in OCR but not 'incorrect' — returning false for incorrect-specific check", category: .evaluation, level: .debug, sessionId: sessionId)
            return false
        }

        logger.log("StrictDetection OCR: Vision OCR inconclusive — falling back to Grok Vision API", category: .evaluation, level: .info, sessionId: sessionId)
        let grokResult = await grokService.analyzeLoginScreenshot(screenshot)
        if let grok = grokResult {
            let errorText = grok.errorText.lowercased()
            if errorText.contains("incorrect") || grok.hasError {
                logger.log("StrictDetection OCR: Grok Vision found error — errorText='\(grok.errorText)' hasError=\(grok.hasError)", category: .evaluation, level: .info, sessionId: sessionId)
                return errorText.contains("incorrect")
            }
        }

        logger.log("StrictDetection OCR: Grok Vision also inconclusive — 'incorrect' NOT found", category: .evaluation, level: .warning, sessionId: sessionId)
        return false
    }
}
