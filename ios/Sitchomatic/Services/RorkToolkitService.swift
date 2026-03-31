import Foundation
import UIKit

// MARK: - Usage Stats

@MainActor
final class GrokUsageStats {
    static let shared = GrokUsageStats()

    private(set) var totalCalls: Int = 0
    private(set) var successfulCalls: Int = 0
    private(set) var failedCalls: Int = 0
    private(set) var totalTokensUsed: Int = 0
    private(set) var lastError: String?
    private(set) var lastCallTime: Date?
    private(set) var currentModel: String = "grok-3-fast"

    var successRate: Double {
        guard totalCalls > 0 else { return 0 }
        return Double(successfulCalls) / Double(totalCalls)
    }

    func recordSuccess(tokens: Int, model: String) {
        totalCalls += 1
        successfulCalls += 1
        totalTokensUsed += tokens
        lastCallTime = Date()
        currentModel = model
    }

    func recordFailure(error: String) {
        totalCalls += 1
        failedCalls += 1
        lastError = error
        lastCallTime = Date()
    }

    func reset() {
        totalCalls = 0
        successfulCalls = 0
        failedCalls = 0
        totalTokensUsed = 0
        lastError = nil
        lastCallTime = nil
    }
}

// MARK: - Models

nonisolated enum GrokModel: String, Sendable {
    case standard = "grok-3-fast"
    case mini = "grok-3-mini-fast"
    case vision = "grok-2-vision-latest"
}

nonisolated struct GrokVisionAnalysisResult: Sendable {
    let loginSuccessful: Bool
    let hasError: Bool
    let errorText: String
    let accountDisabled: Bool
    let isPermanentBan: Bool
    let isTempLock: Bool
    let captchaDetected: Bool
    let ppsrPassed: Bool
    let ppsrDeclined: Bool
    let rawResponse: String
    let confidence: Int
}

// MARK: - Service

@MainActor
final class RorkToolkitService {
    static let shared = RorkToolkitService()

    private let logger = DebugLogger.shared
    private let baseURL = "https://api.x.ai"
    private let maxRetries = 3
    private let visionMaxBytes = 4_000_000

    private var apiKey: String? {
        GrokKeychain.shared.getAPIKey()
    }

    // MARK: Text Generation

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        model: GrokModel = .standard,
        jsonMode: Bool = false,
        temperature: Double = 0.3
    ) async -> String? {
        guard let key = apiKey, !key.isEmpty else {
            logger.log("GrokAI: no API key — call GrokAISetup.bootstrapFromEnvironment()", category: .automation, level: .error)
            return nil
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": temperature,
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        return await callWithRetry(endpoint: "/v1/chat/completions", body: body, key: key, model: model.rawValue)
    }

    func generateFast(systemPrompt: String, userPrompt: String) async -> String? {
        await generateText(systemPrompt: systemPrompt, userPrompt: userPrompt, model: .mini, temperature: 0.1)
    }

    // MARK: Vision Analysis

    func analyzeScreenshotWithVision(
        image: UIImage,
        prompt: String
    ) async -> GrokVisionAnalysisResult? {
        guard let key = apiKey, !key.isEmpty else {
            logger.log("GrokVision: no API key", category: .automation, level: .error)
            return nil
        }

        guard let base64 = encodeImageForVision(image) else {
            logger.log("GrokVision: failed to encode image", category: .automation, level: .error)
            return nil
        }

        let body: [String: Any] = [
            "model": GrokModel.vision.rawValue,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                        ["type": "text", "text": prompt],
                    ],
                ]
            ],
            "temperature": 0.1,
        ]

        guard let rawResponse = await callWithRetry(
            endpoint: "/v1/chat/completions",
            body: body,
            key: key,
            model: GrokModel.vision.rawValue
        ) else {
            return nil
        }

        return parseVisionResponse(rawResponse)
    }

    func analyzeLoginScreenshot(_ image: UIImage) async -> GrokVisionAnalysisResult? {
        let prompt = """
        Analyze this casino/gambling website login page screenshot. Determine the exact result.

        Answer ONLY with JSON in this exact format:
        {
          "loginSuccessful": false,
          "hasError": false,
          "errorText": "",
          "accountDisabled": false,
          "isPermanentBan": false,
          "isTempLock": false,
          "captchaDetected": false,
          "confidence": 90
        }

        Rules:
        - loginSuccessful = true if you see a lobby, dashboard, game grid, or user balance — NOT the login form
        - accountDisabled = true if you see "has been disabled", "temporarily disabled", "account suspended", "contact support"
        - isPermanentBan = true ONLY if text says "has been disabled" (permanent)
        - isTempLock = true ONLY if text says "temporarily disabled"
        - hasError = true if there is a red banner, error message, or "incorrect password"
        - captchaDetected = true if there is a CAPTCHA or "I am not a robot" prompt
        - errorText = the exact error message text visible, empty string if none
        - confidence = 0–100 how confident you are
        """
        return await analyzeScreenshotWithVision(image: image, prompt: prompt)
    }

    func analyzePPSRScreenshot(_ image: UIImage) async -> GrokVisionAnalysisResult? {
        let prompt = """
        Analyze this Australian PPSR vehicle check payment page screenshot.

        Answer ONLY with JSON:
        {
          "ppsrPassed": false,
          "ppsrDeclined": false,
          "hasError": false,
          "errorText": "",
          "confidence": 90
        }

        Rules:
        - ppsrPassed = true if you see a PPSR certificate, success message, or confirmation page
        - ppsrDeclined = true if you see "declined by your institution", "payment failed", "card declined", "insufficient funds"
        - hasError = true for any other visible error or failure message
        - errorText = exact error text or empty string
        """
        return await analyzeScreenshotWithVision(image: image, prompt: prompt)
    }

    // MARK: API Test

    func testConnection() async -> (success: Bool, latencyMs: Int, model: String) {
        guard let key = apiKey, !key.isEmpty else {
            return (false, 0, "")
        }
        let start = Date()
        let result = await generateFast(systemPrompt: "You are a test assistant.", userPrompt: "Reply with exactly: OK")
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        let ok = result?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("OK") == true
        return (ok, latency, GrokModel.mini.rawValue)
    }

    // MARK: - Private

    private func callWithRetry(
        endpoint: String,
        body: [String: Any],
        key: String,
        model: String
    ) async -> String? {
        var lastError = ""
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt - 1)) * 0.5
                try? await Task.sleep(for: .seconds(delay))
            }

            guard let url = URL(string: "\(baseURL)\(endpoint)") else {
                GrokUsageStats.shared.recordFailure(error: "Invalid URL")
                return nil
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 45

            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                GrokUsageStats.shared.recordFailure(error: "Serialization failed")
                return nil
            }
            req.httpBody = httpBody

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 429 || http.statusCode >= 500 {
                    lastError = "HTTP \(http.statusCode)"
                    logger.log("GrokAI: \(lastError) on attempt \(attempt + 1), retrying…", category: .automation, level: .warning)
                    continue
                }

                if http.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    lastError = "HTTP \(http.statusCode): \(body.prefix(120))"
                    GrokUsageStats.shared.recordFailure(error: lastError)
                    logger.log("GrokAI: \(lastError)", category: .automation, level: .error)
                    return nil
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let tokens = (json["usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0
                    GrokUsageStats.shared.recordSuccess(tokens: tokens, model: model)
                    return content
                }

                if let text = String(data: data, encoding: .utf8) {
                    GrokUsageStats.shared.recordSuccess(tokens: 0, model: model)
                    return text
                }

            } catch {
                lastError = error.localizedDescription
                logger.log("GrokAI: request error on attempt \(attempt + 1) — \(lastError)", category: .automation, level: .warning)
            }
        }

        GrokUsageStats.shared.recordFailure(error: lastError)
        logger.log("GrokAI: all \(maxRetries) attempts failed — \(lastError)", category: .automation, level: .error)
        return nil
    }

    private func encodeImageForVision(_ image: UIImage) -> String? {
        let targetSize = CGSize(width: 1280, height: 960)
        let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height, 1.0)
        let resized: UIImage
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            resized = image
        }

        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > visionMaxBytes, quality > 0.3 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        return data?.base64EncodedString()
    }

    private func parseVisionResponse(_ raw: String) -> GrokVisionAnalysisResult {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStr: String
        if let start = cleaned.range(of: "{"), let end = cleaned.range(of: "}", options: .backwards) {
            jsonStr = String(cleaned[start.lowerBound...end.upperBound])
        } else {
            jsonStr = cleaned
        }

        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return GrokVisionAnalysisResult(
                loginSuccessful: dict["loginSuccessful"] as? Bool ?? false,
                hasError: dict["hasError"] as? Bool ?? false,
                errorText: dict["errorText"] as? String ?? "",
                accountDisabled: dict["accountDisabled"] as? Bool ?? false,
                isPermanentBan: dict["isPermanentBan"] as? Bool ?? false,
                isTempLock: dict["isTempLock"] as? Bool ?? false,
                captchaDetected: dict["captchaDetected"] as? Bool ?? false,
                ppsrPassed: dict["ppsrPassed"] as? Bool ?? false,
                ppsrDeclined: dict["ppsrDeclined"] as? Bool ?? false,
                rawResponse: raw,
                confidence: dict["confidence"] as? Int ?? 50
            )
        }

        let lower = raw.lowercased()
        return GrokVisionAnalysisResult(
            loginSuccessful: lower.contains("lobby") || lower.contains("dashboard") || lower.contains("loginsuccessful\": true"),
            hasError: lower.contains("incorrect") || lower.contains("error") || lower.contains("invalid"),
            errorText: "",
            accountDisabled: lower.contains("disabled") || lower.contains("suspended") || lower.contains("banned"),
            isPermanentBan: lower.contains("has been disabled"),
            isTempLock: lower.contains("temporarily disabled"),
            captchaDetected: lower.contains("captcha") || lower.contains("robot"),
            ppsrPassed: lower.contains("passed") || lower.contains("certificate"),
            ppsrDeclined: lower.contains("declined") || lower.contains("institution"),
            rawResponse: raw,
            confidence: 30
        )
    }
}
