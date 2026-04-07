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

    func analyzePPSRResponse(pageContent: String) async -> AIAnalysisPPSRResult? {
        let truncated = String(pageContent.prefix(2500))
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

            Page content:
            \(truncated)
            """
            if let raw = await grok.generateText(systemPrompt: sys, userPrompt: prompt, jsonMode: true) {
                return parsePPSRJSON(raw, fallbackContent: truncated)
            }
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You analyze PPSR vehicle check responses. Respond with JSON: passed (bool), declined (bool), summary (string), confidence (0-100), errorType (string), suggestedAction (string)."
                )
                let response = try await session.respond(to: "Analyze:\n\(truncated)")
                return parsePPSRJSON(response.content, fallbackContent: truncated)
            } catch {}
        }
        #endif

        return heuristicPPSRAnalysis(pageContent: truncated)
    }

    func analyzeLoginPage(pageContent: String, ocrTexts: [String]) async -> AIAnalysisLoginResult? {
        nil
    }

    func mapOCRToFields(ocrTexts: [String]) async -> AIFieldMappingResult? {
        nil
    }

    func predictFlowOutcome(currentStep: String, pageContent: String, previousActions: [String]) async -> AIFlowPredictionResult? {
        nil
    }

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

    private func extractJSON(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.range(of: "{"), let end = cleaned.range(of: "}", options: .backwards) {
            return String(cleaned[start.lowerBound...end.upperBound])
        }
        return cleaned
    }

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
}
