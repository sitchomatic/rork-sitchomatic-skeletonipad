import Foundation
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum VisionAnalysisSite: String, Sendable {
    case joe
    case ignition
}

nonisolated enum VisionAnalysisPhase: String, Sendable {
    case login
    case ppsr
    case settlement
    case disabledCheck
}

nonisolated struct VisionContext: Sendable {
    let site: VisionAnalysisSite
    let phase: VisionAnalysisPhase
    let currentURL: String
    let sessionId: String

    init(site: VisionAnalysisSite = .joe, phase: VisionAnalysisPhase = .login, currentURL: String = "", sessionId: String = "") {
        self.site = site
        self.phase = phase
        self.currentURL = currentURL
        self.sessionId = sessionId
    }
}

nonisolated struct VisionOutcome: Sendable {
    let outcome: LoginOutcome
    let confidence: Int
    let reasoning: String
    let errorText: String
    let isPageSettled: Bool
    let isPageBlank: Bool
    let ppsrPassed: Bool
    let ppsrDeclined: Bool
    let rawResponse: String

    static let unsureDefault = VisionOutcome(
        outcome: .unsure, confidence: 0, reasoning: "No analysis available",
        errorText: "", isPageSettled: false, isPageBlank: false,
        ppsrPassed: false, ppsrDeclined: false, rawResponse: ""
    )
}

@MainActor
final class UnifiedAIVisionService {
    static let shared = UnifiedAIVisionService()

    private let grok = RorkToolkitService.shared
    private let logger = DebugLogger.shared

    func analyzeScreenshot(_ image: UIImage, context: VisionContext) async -> VisionOutcome {
        let startTime = Date()

        let grokResult = await grok.analyzeUnifiedVision(image: image, context: context)
        if let result = grokResult {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            logger.log("UnifiedVision: Grok returned \(result.outcome) conf=\(result.confidence)% in \(elapsed)ms", category: .evaluation, level: result.outcome == .success ? .success : .info, sessionId: context.sessionId)
            return result
        }

        logger.log("UnifiedVision: Grok unavailable — falling back to on-device OCR", category: .evaluation, level: .warning, sessionId: context.sessionId)
        let fallbackResult = await onDeviceOCRFallback(image: image, context: context)
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        logger.log("UnifiedVision: OCR fallback returned \(fallbackResult.outcome) conf=\(fallbackResult.confidence)% in \(elapsed)ms", category: .evaluation, level: .info, sessionId: context.sessionId)
        return fallbackResult
    }

    func analyzeForSettlement(_ image: UIImage, context: VisionContext) async -> VisionOutcome {
        let settlementContext = VisionContext(site: context.site, phase: .settlement, currentURL: context.currentURL, sessionId: context.sessionId)
        return await analyzeScreenshot(image, context: settlementContext)
    }

    private func onDeviceOCRFallback(image: UIImage, context: VisionContext) async -> VisionOutcome {
        guard let cgImage = image.cgImage else {
            return VisionOutcome(outcome: .unsure, confidence: 0, reasoning: "No image data", errorText: "", isPageSettled: false, isPageBlank: true, ppsrPassed: false, ppsrDeclined: false, rawResponse: "")
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return VisionOutcome(outcome: .unsure, confidence: 0, reasoning: "OCR failed: \(error.localizedDescription)", errorText: "", isPageSettled: false, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: "")
        }

        let allText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        let isBlank = allText.trimmingCharacters(in: .whitespacesAndNewlines).count < 10

        if isBlank {
            return VisionOutcome(outcome: .unsure, confidence: 20, reasoning: "Page appears blank — minimal OCR text", errorText: "", isPageSettled: false, isPageBlank: true, ppsrPassed: false, ppsrDeclined: false, rawResponse: allText)
        }

        let ocrOutcome = classifyOCRText(allText, context: context)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let appleResult = await appleAIFallback(ocrText: allText, context: context) {
                return appleResult
            }
        }
        #endif

        return ocrOutcome
    }

    private func classifyOCRText(_ text: String, context: VisionContext) -> VisionOutcome {
        let lower = text.lowercased()

        if context.phase == .ppsr {
            let passed = lower.contains("search complete") || lower.contains("no interests") || lower.contains("certificate")
            let declined = lower.contains("institution") || lower.contains("declined") || lower.contains("payment failed") || lower.contains("insufficient")
            return VisionOutcome(
                outcome: passed ? .success : declined ? .noAcc : .unsure,
                confidence: (passed || declined) ? 65 : 30,
                reasoning: passed ? "PPSR certificate/success markers in OCR" : declined ? "PPSR decline markers in OCR" : "No PPSR markers found",
                errorText: declined ? String(text.prefix(200)) : "",
                isPageSettled: true, isPageBlank: false,
                ppsrPassed: passed, ppsrDeclined: declined,
                rawResponse: String(text.prefix(500))
            )
        }

        if lower.contains("has been disabled") {
            return VisionOutcome(outcome: .permDisabled, confidence: 95, reasoning: "OCR: 'has been disabled' — permanent ban", errorText: "has been disabled", isPageSettled: true, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
        }
        if lower.contains("temporarily disabled") {
            return VisionOutcome(outcome: .tempDisabled, confidence: 95, reasoning: "OCR: 'temporarily disabled' — temp lock", errorText: "temporarily disabled", isPageSettled: true, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
        }

        let successMarkers = ["recommended for you", "last played", "my account", "balance", "deposit", "dashboard", "logout"]
        for marker in successMarkers {
            if lower.contains(marker) {
                return VisionOutcome(outcome: .success, confidence: 85, reasoning: "OCR: lobby marker '\(marker)' detected", errorText: "", isPageSettled: true, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
            }
        }

        let smsMarkers = ["verification code", "verify your phone", "enter the code", "sms", "text message", "phone verification"]
        for marker in smsMarkers {
            if lower.contains(marker) {
                return VisionOutcome(outcome: .smsDetected, confidence: 80, reasoning: "OCR: SMS marker '\(marker)' detected", errorText: marker, isPageSettled: true, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
            }
        }

        if lower.contains("incorrect") || lower.contains("invalid") || lower.contains("wrong password") {
            return VisionOutcome(outcome: .noAcc, confidence: 80, reasoning: "OCR: incorrect/invalid password marker", errorText: "incorrect", isPageSettled: true, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
        }

        let isSettled = context.phase == .settlement
        return VisionOutcome(outcome: .unsure, confidence: 25, reasoning: "OCR: no definitive markers found in text", errorText: "", isPageSettled: isSettled, isPageBlank: false, ppsrPassed: false, ppsrDeclined: false, rawResponse: String(text.prefix(500)))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func appleAIFallback(ocrText: String, context: VisionContext) async -> VisionOutcome? {
        do {
            let instructions: String
            switch context.phase {
            case .login, .settlement, .disabledCheck:
                instructions = "You analyze casino login page OCR text. Respond ONLY with JSON: {\"outcome\":\"success|noAcc|permDisabled|tempDisabled|smsDetected|unsure\",\"confidence\":0-100,\"reasoning\":\"...\",\"errorText\":\"...\",\"isPageSettled\":true/false}"
            case .ppsr:
                instructions = "You analyze PPSR payment page OCR text. Respond ONLY with JSON: {\"outcome\":\"success|noAcc|unsure\",\"confidence\":0-100,\"reasoning\":\"...\",\"ppsrPassed\":true/false,\"ppsrDeclined\":true/false}"
            }

            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Analyze this OCR text:\n\(String(ocrText.prefix(2000)))")
            return parseAppleAIResponse(response.content, context: context, ocrText: ocrText)
        } catch {
            logger.logError("UnifiedVision: Apple AI fallback failed", error: error, category: .evaluation)
            return nil
        }
    }
    #endif

    private func parseAppleAIResponse(_ text: String, context: VisionContext, ocrText: String) -> VisionOutcome? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.range(of: "{"), let end = cleaned.range(of: "}", options: .backwards) else { return nil }
        let jsonStr = String(cleaned[start.lowerBound...end.upperBound])
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let outcomeStr = dict["outcome"] as? String ?? "unsure"
        let outcome: LoginOutcome
        switch outcomeStr.lowercased() {
        case "success": outcome = .success
        case "noacc": outcome = .noAcc
        case "permdisabled": outcome = .permDisabled
        case "tempdisabled": outcome = .tempDisabled
        case "smsdetected": outcome = .smsDetected
        default: outcome = .unsure
        }

        return VisionOutcome(
            outcome: outcome,
            confidence: dict["confidence"] as? Int ?? 40,
            reasoning: "AppleAI: \(dict["reasoning"] as? String ?? outcomeStr)",
            errorText: dict["errorText"] as? String ?? "",
            isPageSettled: dict["isPageSettled"] as? Bool ?? true,
            isPageBlank: false,
            ppsrPassed: dict["ppsrPassed"] as? Bool ?? false,
            ppsrDeclined: dict["ppsrDeclined"] as? Bool ?? false,
            rawResponse: String(ocrText.prefix(500))
        )
    }
}
