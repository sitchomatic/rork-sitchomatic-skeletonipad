import Foundation
import UIKit

@MainActor
final class AIVisionSettlementService {
    static let shared = AIVisionSettlementService()

    private let vision = UnifiedAIVisionService.shared
    private let logger = DebugLogger.shared

    nonisolated struct SettlementResult: Sendable {
        let settled: Bool
        let outcome: VisionOutcome
        let durationMs: Int
        let screenshotsTaken: Int
        let reason: String
    }

    private let pollIntervals: [Int] = [500, 1500, 3000, 5000]

    func waitForSettlement(
        captureScreenshot: @escaping () async -> UIImage?,
        context: VisionContext,
        maxTimeoutMs: Int = 8000
    ) async -> SettlementResult {
        let start = Date()
        var screenshotCount = 0

        for intervalMs in pollIntervals {
            guard !Task.isCancelled else {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                return SettlementResult(settled: false, outcome: .unsureDefault, durationMs: ms, screenshotsTaken: screenshotCount, reason: "Task cancelled")
            }

            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            if elapsed >= maxTimeoutMs {
                break
            }

            let remainingMs = intervalMs - elapsed
            if remainingMs > 0 {
                try? await Task.sleep(for: .milliseconds(remainingMs))
            }

            guard let screenshot = await captureScreenshot() else {
                logger.log("AISettlement: screenshot capture failed at \(intervalMs)ms", category: .evaluation, level: .warning, sessionId: context.sessionId)
                continue
            }
            screenshotCount += 1

            let result = await vision.analyzeForSettlement(screenshot, context: context)

            if result.outcome != .unsure && result.confidence >= 60 {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                logger.log("AISettlement: settled at \(ms)ms — \(result.outcome) conf=\(result.confidence)%", category: .evaluation, level: .success, sessionId: context.sessionId)
                return SettlementResult(settled: true, outcome: result, durationMs: ms, screenshotsTaken: screenshotCount, reason: "AI detected definitive outcome: \(result.reasoning)")
            }

            if result.isPageBlank {
                logger.log("AISettlement: page blank at \(intervalMs)ms — continuing", category: .evaluation, level: .debug, sessionId: context.sessionId)
                continue
            }

            if result.isPageSettled && result.outcome == .unsure {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                logger.log("AISettlement: page settled but unsure at \(ms)ms", category: .evaluation, level: .warning, sessionId: context.sessionId)
                return SettlementResult(settled: true, outcome: result, durationMs: ms, screenshotsTaken: screenshotCount, reason: "Page settled but outcome uncertain")
            }
        }

        let finalMs = Int(Date().timeIntervalSince(start) * 1000)

        if let finalScreenshot = await captureScreenshot() {
            screenshotCount += 1
            let finalResult = await vision.analyzeScreenshot(finalScreenshot, context: context)
            logger.log("AISettlement: timeout at \(finalMs)ms — final analysis: \(finalResult.outcome) conf=\(finalResult.confidence)%", category: .evaluation, level: .warning, sessionId: context.sessionId)
            return SettlementResult(settled: true, outcome: finalResult, durationMs: finalMs, screenshotsTaken: screenshotCount, reason: "Timeout — final screenshot analysis")
        }

        return SettlementResult(settled: false, outcome: .unsureDefault, durationMs: finalMs, screenshotsTaken: screenshotCount, reason: "Timeout — no final screenshot")
    }
}
