import Foundation
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated struct AIAnalysisPPSRResult: Sendable {
    let passed: Bool
    let declined: Bool
    let summary: String
    let confidence: Int
    let errorType: String
    let suggestedAction: String
}

nonisolated struct AIAnalysisLoginResult: Sendable {
    let loginSuccessful: Bool
    let hasError: Bool
    let errorText: String
    let accountDisabled: Bool
    let suggestedAction: String
    let confidence: Int
}

nonisolated struct AIFieldMappingResult: Sendable {
    let emailLabels: [String]
    let passwordLabels: [String]
    let buttonLabels: [String]
    let isStandard: Bool
    let confidence: Int
}

nonisolated struct AIFlowPredictionResult: Sendable {
    let nextAction: String
    let reason: String
    let shouldContinue: Bool
    let riskLevel: String
}

@MainActor
final class OnDeviceAIService {
    static let shared = OnDeviceAIService()

    private let logger = DebugLogger.shared
    private let grok = RorkToolkitService.shared

    var isAvailable: Bool {
        GrokAISetup.isConfigured || appleModelAvailable
    }

    private var appleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - PPSR Analysis (Grok → Apple → Heuristic)

    func analyzePPSRResponse(pageContent: String) async -> AIAnalysisPPSRResult? {
        let truncated = String(pageContent.prefix(2500))

        // 1. Grok API first
        if GrokAISetup.isConfigured {
            let sys = "You analyze PPSR vehicle check responses from the Australian PPSR registry. Determine if the check passed or payment was declined. Respond with valid JSON only."
            let prompt = """
            Analyze this PPSR response page content and return JSON:
            {
              "passed": false,
              "declined": false,
              "summary": "",
              "confidence": 90,
              "errorType": "",
              "suggestedAction": ""
            }

            errorType options: "none", "institution_decline", "expired_card", "insufficient_funds", "network_error"
            suggestedAction options: "proceed", "rotate_card", "retry"

            Page content:
            \(truncated)
            """
            if let raw = await grok.generateText(systemPrompt: sys, userPrompt: prompt, jsonMode: true) {
                let result = parsePPSRJSON(raw, fallbackContent: truncated)
                logger.log("GrokAI PPSR: passed=\(result.passed) declined=\(result.declined) conf=\(result.confidence)%", category: .automation, level: result.passed ? .success : .warning)
                return result
            }
        }

        // 2. Apple on-device fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You analyze PPSR vehicle check responses. Respond with JSON: passed (bool), declined (bool), summary (string), confidence (0-100), errorType (string), suggestedAction (string)."
                )
                let response = try await session.respond(to: "Analyze:\n\(truncated)")
                let result = parsePPSRJSON(response.content, fallbackContent: truncated)
                logger.log("AppleAI PPSR fallback: passed=\(result.passed) conf=\(result.confidence)%", category: .automation, level: .info)
                return result
            } catch {
                logger.logError("AppleAI: PPSR analysis failed", error: error, category: .automation)
            }
        }
        #endif

        // 3. Heuristic fallback
        return heuristicPPSRAnalysis(pageContent: truncated)
    }

    // MARK: - Login Analysis (Grok → Apple → Heuristic)

    func analyzeLoginPage(pageContent: String, ocrTexts: [String]) async -> AIAnalysisLoginResult? {
        let truncatedContent = String(pageContent.prefix(1800))
        let ocrSummary = ocrTexts.prefix(40).joined(separator: " | ")

        // 1. Grok API first
        if GrokAISetup.isConfigured {
            let sys = "You analyze casino/gambling website login page outcomes. Respond with valid JSON only."
            let prompt = """
            Analyze this login page and return JSON:
            {
              "loginSuccessful": false,
              "hasError": false,
              "errorText": "",
              "accountDisabled": false,
              "suggestedAction": "",
              "confidence": 90
            }

            suggestedAction options: "login_success", "account_disabled", "wrong_credentials", "captcha_detected", "retry_login", "unknown"

            Page content: \(truncatedContent)
            OCR text: \(ocrSummary)
            """
            if let raw = await grok.generateText(systemPrompt: sys, userPrompt: prompt, jsonMode: true) {
                let result = parseLoginJSON(raw, fallbackContent: truncatedContent)
                logger.log("GrokAI Login: success=\(result.loginSuccessful) error=\(result.hasError) disabled=\(result.accountDisabled) conf=\(result.confidence)%", category: .automation, level: result.loginSuccessful ? .success : .info)
                return result
            }
        }

        // 2. Apple on-device fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You analyze login pages for gambling websites. Respond with JSON: loginSuccessful, hasError, errorText, accountDisabled, suggestedAction, confidence."
                )
                let prompt = "Page: \(truncatedContent)\nOCR: \(ocrSummary)"
                let response = try await session.respond(to: prompt)
                let result = parseLoginJSON(response.content, fallbackContent: truncatedContent)
                logger.log("AppleAI Login fallback: success=\(result.loginSuccessful) conf=\(result.confidence)%", category: .automation, level: .info)
                return result
            } catch {
                logger.logError("AppleAI: login analysis failed", error: error, category: .automation)
            }
        }
        #endif

        // 3. Heuristic fallback
        return heuristicLoginAnalysis(pageContent: truncatedContent)
    }

    // MARK: - OCR Field Mapping (Grok → Apple → Heuristic)

    func mapOCRToFields(ocrTexts: [String]) async -> AIFieldMappingResult? {
        let textList = ocrTexts.prefix(40).joined(separator: "\n")

        // 1. Grok fast model
        if GrokAISetup.isConfigured {
            let sys = "You identify login form fields from OCR text. Respond with valid JSON only."
            let prompt = """
            Identify login form elements from this OCR text and return JSON:
            {
              "emailLabels": [],
              "passwordLabels": [],
              "buttonLabels": [],
              "isStandard": true,
              "confidence": 90
            }

            OCR text:
            \(textList)
            """
            if let raw = await grok.generateFast(systemPrompt: sys, userPrompt: prompt) {
                return parseFieldMappingJSON(raw, ocrTexts: ocrTexts)
            }
        }

        // 2. Apple on-device fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "Identify login form elements from OCR. Respond with JSON: emailLabels, passwordLabels, buttonLabels, isStandard, confidence."
                )
                let response = try await session.respond(to: "Identify:\n\(textList)")
                return parseFieldMappingJSON(response.content, ocrTexts: ocrTexts)
            } catch {}
        }
        #endif

        // 3. Heuristic fallback
        return heuristicFieldMapping(ocrTexts: ocrTexts)
    }

    // MARK: - Flow Prediction (Grok → Apple → Heuristic)

    func predictFlowOutcome(currentStep: String, pageContent: String, previousActions: [String]) async -> AIFlowPredictionResult? {
        let truncated = String(pageContent.prefix(1200))
        let recentActions = previousActions.suffix(5).joined(separator: "\n")

        // 1. Grok fast model
        if GrokAISetup.isConfigured {
            let sys = "You predict next steps in automated web flows. Respond with valid JSON only."
            let prompt = """
            Predict the next action and return JSON:
            {
              "nextAction": "click",
              "reason": "",
              "shouldContinue": true,
              "riskLevel": "low"
            }

            riskLevel options: "low", "medium", "high", "critical"
            nextAction options: "click", "type", "wait", "submit", "reload", "abort"

            Current step: \(currentStep)
            Recent actions: \(recentActions)
            Page content: \(truncated)
            """
            if let raw = await grok.generateFast(systemPrompt: sys, userPrompt: prompt) {
                return parseFlowPredictionJSON(raw)
            }
        }

        // 2. Apple on-device fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "Predict automation flow next steps. Respond with JSON: nextAction, reason, shouldContinue, riskLevel."
                )
                let prompt = "Step: \(currentStep)\nActions:\n\(recentActions)\nPage:\n\(truncated)"
                let response = try await session.respond(to: prompt)
                return parseFlowPredictionJSON(response.content)
            } catch {}
        }
        #endif

        // 3. Heuristic fallback
        return AIFlowPredictionResult(nextAction: "click", reason: "Heuristic default", shouldContinue: true, riskLevel: "low")
    }

    // MARK: - Email Variant (Grok → Apple)

    func generateVariantEmail(base: String) async -> String? {
        if GrokAISetup.isConfigured {
            let result = await grok.generateFast(
                systemPrompt: "Generate a Gmail dot-trick variant of the given email. Return only the email address, nothing else.",
                userPrompt: "Create a variant of: \(base)"
            )
            if let r = result?.trimmingCharacters(in: .whitespacesAndNewlines), r.contains("@") {
                return r
            }
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(instructions: "Generate a slight variation of an email using dot tricks. Return only the email.")
                let response = try await session.respond(to: "Variant of: \(base)")
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("@") { return trimmed }
            } catch {}
        }
        #endif

        return nil
    }

    // MARK: - JSON Parsers

    private func parsePPSRJSON(_ text: String, fallbackContent: String) -> AIAnalysisPPSRResult {
        let jsonStr = extractJSON(from: text)
        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let passed = dict["passed"] as? Bool ?? false
            let declined = dict["declined"] as? Bool ?? false
            return AIAnalysisPPSRResult(
                passed: passed && !declined,
                declined: declined,
                summary: dict["summary"] as? String ?? String(text.prefix(200)),
                confidence: dict["confidence"] as? Int ?? 60,
                errorType: dict["errorType"] as? String ?? "none",
                suggestedAction: dict["suggestedAction"] as? String ?? "retry"
            )
        }
        return heuristicPPSRAnalysis(pageContent: fallbackContent)!
    }

    private func parseLoginJSON(_ text: String, fallbackContent: String) -> AIAnalysisLoginResult {
        let jsonStr = extractJSON(from: text)
        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return AIAnalysisLoginResult(
                loginSuccessful: dict["loginSuccessful"] as? Bool ?? false,
                hasError: dict["hasError"] as? Bool ?? false,
                errorText: dict["errorText"] as? String ?? "",
                accountDisabled: dict["accountDisabled"] as? Bool ?? false,
                suggestedAction: dict["suggestedAction"] as? String ?? "unknown",
                confidence: dict["confidence"] as? Int ?? 50
            )
        }
        return heuristicLoginAnalysis(pageContent: fallbackContent)!
    }

    private func parseFieldMappingJSON(_ text: String, ocrTexts: [String]) -> AIFieldMappingResult {
        let jsonStr = extractJSON(from: text)
        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return AIFieldMappingResult(
                emailLabels: dict["emailLabels"] as? [String] ?? [],
                passwordLabels: dict["passwordLabels"] as? [String] ?? [],
                buttonLabels: dict["buttonLabels"] as? [String] ?? [],
                isStandard: dict["isStandard"] as? Bool ?? true,
                confidence: dict["confidence"] as? Int ?? 50
            )
        }
        return heuristicFieldMapping(ocrTexts: ocrTexts)!
    }

    private func parseFlowPredictionJSON(_ text: String) -> AIFlowPredictionResult {
        let jsonStr = extractJSON(from: text)
        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return AIFlowPredictionResult(
                nextAction: dict["nextAction"] as? String ?? "click",
                reason: dict["reason"] as? String ?? "",
                shouldContinue: dict["shouldContinue"] as? Bool ?? true,
                riskLevel: dict["riskLevel"] as? String ?? "low"
            )
        }
        let lower = text.lowercased()
        return AIFlowPredictionResult(
            nextAction: lower.contains("click") ? "click" : lower.contains("type") ? "type" : "wait",
            reason: String(text.prefix(200)),
            shouldContinue: !lower.contains("abort") && !lower.contains("critical"),
            riskLevel: lower.contains("critical") ? "critical" : lower.contains("high") ? "high" : "low"
        )
    }

    private func extractJSON(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.range(of: "{"), let end = cleaned.range(of: "}", options: .backwards) {
            return String(cleaned[start.lowerBound...end.upperBound])
        }
        return cleaned
    }

    // MARK: - Heuristic Fallbacks

    private func heuristicPPSRAnalysis(pageContent: String) -> AIAnalysisPPSRResult? {
        let lower = pageContent.lowercased()
        let passed = lower.contains("search complete") || lower.contains("no interests") || lower.contains("certificate")
        let declined = lower.contains("institution") || lower.contains("declined") || lower.contains("payment failed") || lower.contains("insufficient")

        let errorType: String
        if lower.contains("institution") { errorType = "institution_decline" }
        else if lower.contains("expired") { errorType = "expired_card" }
        else if lower.contains("insufficient") { errorType = "insufficient_funds" }
        else if declined { errorType = "institution_decline" }
        else { errorType = "none" }

        return AIAnalysisPPSRResult(
            passed: passed && !declined,
            declined: declined,
            summary: String(pageContent.prefix(150)),
            confidence: (passed || declined) ? 60 : 30,
            errorType: errorType,
            suggestedAction: passed ? "proceed" : declined ? "rotate_card" : "retry"
        )
    }

    private func heuristicLoginAnalysis(pageContent: String) -> AIAnalysisLoginResult? {
        let lower = pageContent.lowercased()
        let success = lower.contains("lobby") || lower.contains("dashboard") || lower.contains("balance") || lower.contains("welcome back")
        let disabled = lower.contains("has been disabled") || lower.contains("temporarily disabled") || lower.contains("suspended") || lower.contains("banned")
        let hasError = lower.contains("incorrect") || lower.contains("invalid") || lower.contains("error")

        let action: String
        if success { action = "login_success" }
        else if disabled { action = "account_disabled" }
        else if hasError { action = "wrong_credentials" }
        else { action = "unknown" }

        return AIAnalysisLoginResult(
            loginSuccessful: success && !hasError,
            hasError: hasError,
            errorText: hasError ? String(pageContent.prefix(100)) : "",
            accountDisabled: disabled,
            suggestedAction: action,
            confidence: (success || disabled) ? 55 : 30
        )
    }

    private func heuristicFieldMapping(ocrTexts: [String]) -> AIFieldMappingResult? {
        let emailKeywords = ["email", "username", "e-mail", "user name"]
        let passKeywords = ["password", "pass", "pin"]
        let buttonKeywords = ["login", "log in", "sign in", "submit"]

        let emailLabels = ocrTexts.filter { t in emailKeywords.contains { t.lowercased().contains($0) } }
        let passLabels = ocrTexts.filter { t in passKeywords.contains { t.lowercased().contains($0) } }
        let btnLabels = ocrTexts.filter { t in buttonKeywords.contains { t.lowercased().contains($0) } }

        return AIFieldMappingResult(
            emailLabels: emailLabels,
            passwordLabels: passLabels,
            buttonLabels: btnLabels,
            isStandard: !emailLabels.isEmpty && !passLabels.isEmpty,
            confidence: (!emailLabels.isEmpty && !passLabels.isEmpty) ? 55 : 25
        )
    }
}
