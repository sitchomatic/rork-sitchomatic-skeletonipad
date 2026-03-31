import Foundation
import Vision
import UIKit

@MainActor
class VisionTextCropService {
    static let shared = VisionTextCropService()

    private let logger = DebugLogger.shared

    nonisolated struct CropResult: Sendable {
        let croppedImage: UIImage
        let fullImage: UIImage
        let detectedTexts: [DetectedTextBlock]
        let crucialKeywords: [String]
        let cropRect: CGRect
        let processingTimeMs: Int
    }

    nonisolated struct DetectedTextBlock: Sendable {
        let text: String
        let boundingBox: CGRect
        let confidence: Float
        let isCrucial: Bool
    }

    nonisolated struct AnalysisResult: Sendable {
        let allText: String
        let crucialMatches: [String]
        let detectedOutcome: DetectedOutcome
        let confidence: Double
        let textBlocks: [DetectedTextBlock]
        let processingTimeMs: Int
    }

    nonisolated enum DetectedOutcome: String, Sendable {
        case success
        case incorrectPassword
        case noAccount
        case permDisabled
        case tempDisabled
        case smsVerification
        case errorBanner
        case unknown

        /// Paired string label matching the Apple Vision OCR Blueprint format.
        var pairedLabel: String {
            switch self {
            case .success: "Success"
            case .permDisabled: "Perm Disabled"
            case .tempDisabled: "Temp Disabled"
            case .noAccount, .incorrectPassword: "No Acc"
            case .smsVerification: "SMS Detected"
            case .errorBanner: "Error"
            case .unknown: "Unsure"
            }
        }
    }

    // MARK: - 100/100 Strict OCR Triggers (Apple Vision Blueprint)

    private let crucialKeywords: [String] = [
        // Absolute Priority Triggers (100/100 weight)
        "has been disabled",
        "temporarily disabled",
        // Secondary Logic — Success
        "my account", "balance", "deposit", "welcome", "dashboard",
        "logout", "log out", "successfully", "logged in",
        // Secondary Logic — No Account
        "incorrect", "not find", "no account", "invalid",
        "incorrect password", "wrong password",
        // Tertiary
        "error", "failed",
        "sms", "verification code", "verify your phone", "enter the code",
    ]

    /// Outcome patterns ordered by strict 100/100 weight priority.
    /// "has been disabled" and "temporarily disabled" are absolute — they override everything.
    private let outcomePatterns: [(pattern: String, outcome: DetectedOutcome)] = [
        // 100/100 Strict Triggers (absolute priority, checked first)
        ("has been disabled", .permDisabled),
        ("temporarily disabled", .tempDisabled),
        // Secondary Logic — Success
        ("my account", .success),
        ("balance", .success),
        ("deposit", .success),
        ("welcome", .success),
        ("dashboard", .success),
        ("logout", .success),
        // Secondary Logic — No Account
        ("incorrect", .noAccount),
        ("not find", .noAccount),
        ("no account", .noAccount),
        ("invalid", .noAccount),
        ("incorrect password", .noAccount),
        ("wrong password", .noAccount),
        // Tertiary
        ("verification code", .smsVerification),
        ("verify your phone", .smsVerification),
        ("enter the code", .smsVerification),
    ]

    func analyzeScreenshot(_ image: UIImage) async -> AnalysisResult {
        let startTime = Date()
        guard let cgImage = image.cgImage else {
            return AnalysisResult(allText: "", crucialMatches: [], detectedOutcome: .unknown, confidence: 0, textBlocks: [], processingTimeMs: 0)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.logError("VisionTextCrop: OCR failed", error: error, category: .screenshot)
            return AnalysisResult(allText: "", crucialMatches: [], detectedOutcome: .unknown, confidence: 0, textBlocks: [], processingTimeMs: 0)
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        var textBlocks: [DetectedTextBlock] = []
        var allTextParts: [String] = []

        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let pixelRect = CGRect(
                x: box.origin.x * imageSize.width,
                y: (1 - box.origin.y - box.height) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )

            let lower = candidate.string.lowercased()
            let isCrucial = crucialKeywords.contains { lower.contains($0) }

            textBlocks.append(DetectedTextBlock(
                text: candidate.string,
                boundingBox: pixelRect,
                confidence: candidate.confidence,
                isCrucial: isCrucial
            ))
            allTextParts.append(candidate.string)
        }

        let allText = allTextParts.joined(separator: " ")
        let allLower = allText.lowercased()

        var crucialMatches: [String] = []
        var detectedOutcome: DetectedOutcome = .unknown
        var bestConfidence: Double = 0

        for (pattern, outcome) in outcomePatterns {
            if allLower.contains(pattern) {
                crucialMatches.append(pattern)
                if detectedOutcome == .unknown || priorityOf(outcome) > priorityOf(detectedOutcome) {
                    detectedOutcome = outcome
                    bestConfidence = 0.85
                }
            }
        }

        if crucialMatches.isEmpty {
            let weakSignals: [(String, DetectedOutcome, Double)] = [
                ("error", .errorBanner, 0.3),
            ]
            for (term, outcome, conf) in weakSignals {
                if allLower.contains(term) {
                    crucialMatches.append(term)
                    if conf > bestConfidence {
                        detectedOutcome = outcome
                        bestConfidence = conf
                    }
                }
            }
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        logger.log("VisionTextCrop: analyzed \(textBlocks.count) blocks, \(crucialMatches.count) crucial matches, outcome=\(detectedOutcome.rawValue) in \(elapsed)ms", category: .screenshot, level: crucialMatches.isEmpty ? .debug : .info)

        return AnalysisResult(
            allText: allText,
            crucialMatches: crucialMatches,
            detectedOutcome: detectedOutcome,
            confidence: bestConfidence,
            textBlocks: textBlocks,
            processingTimeMs: elapsed
        )
    }

    func smartCrop(_ image: UIImage, analysis: AnalysisResult? = nil) async -> CropResult {
        let startTime = Date()
        let analysisResult: AnalysisResult
        if let existing = analysis {
            analysisResult = existing
        } else {
            analysisResult = await analyzeScreenshot(image)
        }

        guard let cgImage = image.cgImage else {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return CropResult(croppedImage: image, fullImage: image, detectedTexts: [], crucialKeywords: [], cropRect: .zero, processingTimeMs: elapsed)
        }

        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))

        let crucialBlocks = analysisResult.textBlocks.filter(\.isCrucial)
        guard !crucialBlocks.isEmpty else {
            let allBlocks = analysisResult.textBlocks
            if !allBlocks.isEmpty {
                let textRegion = computeTextBodyBounds(blocks: allBlocks, imageSize: imageSize)
                if let cropped = cropImage(cgImage, to: textRegion, padding: 30, imageSize: imageSize, original: image) {
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    return CropResult(croppedImage: cropped, fullImage: image, detectedTexts: allBlocks, crucialKeywords: analysisResult.crucialMatches, cropRect: textRegion, processingTimeMs: elapsed)
                }
            }
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return CropResult(croppedImage: image, fullImage: image, detectedTexts: analysisResult.textBlocks, crucialKeywords: analysisResult.crucialMatches, cropRect: .zero, processingTimeMs: elapsed)
        }

        var nearbyBlocks: [DetectedTextBlock] = crucialBlocks
        for crucialBlock in crucialBlocks {
            let expandedRect = crucialBlock.boundingBox.insetBy(dx: -80, dy: -60)
            for block in analysisResult.textBlocks where !block.isCrucial {
                if expandedRect.intersects(block.boundingBox) {
                    nearbyBlocks.append(block)
                }
            }
        }

        let textBodyRect = computeTextBodyBounds(blocks: nearbyBlocks, imageSize: imageSize)

        if let cropped = cropImage(cgImage, to: textBodyRect, padding: 40, imageSize: imageSize, original: image) {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            logger.log("VisionTextCrop: smart cropped to \(Int(textBodyRect.width))x\(Int(textBodyRect.height)) from \(Int(imageSize.width))x\(Int(imageSize.height)) (\(crucialBlocks.count) crucial blocks) in \(elapsed)ms", category: .screenshot, level: .info)
            return CropResult(croppedImage: cropped, fullImage: image, detectedTexts: nearbyBlocks, crucialKeywords: analysisResult.crucialMatches, cropRect: textBodyRect, processingTimeMs: elapsed)
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        return CropResult(croppedImage: image, fullImage: image, detectedTexts: analysisResult.textBlocks, crucialKeywords: analysisResult.crucialMatches, cropRect: .zero, processingTimeMs: elapsed)
    }

    private func computeTextBodyBounds(blocks: [DetectedTextBlock], imageSize: CGSize) -> CGRect {
        guard !blocks.isEmpty else { return CGRect(origin: .zero, size: imageSize) }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for block in blocks {
            minX = min(minX, block.boundingBox.minX)
            minY = min(minY, block.boundingBox.minY)
            maxX = max(maxX, block.boundingBox.maxX)
            maxY = max(maxY, block.boundingBox.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func cropImage(_ cgImage: CGImage, to rect: CGRect, padding: CGFloat, imageSize: CGSize, original: UIImage) -> UIImage? {
        let cropRect = CGRect(
            x: max(0, rect.origin.x - padding),
            y: max(0, rect.origin.y - padding),
            width: min(imageSize.width - max(0, rect.origin.x - padding), rect.width + padding * 2),
            height: min(imageSize.height - max(0, rect.origin.y - padding), rect.height + padding * 2)
        )

        guard cropRect.width > 50, cropRect.height > 30 else { return nil }
        guard cropRect.width < imageSize.width * 0.95 || cropRect.height < imageSize.height * 0.95 else { return nil }

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: original.scale, orientation: original.imageOrientation)
    }

    private func priorityOf(_ outcome: DetectedOutcome) -> Int {
        switch outcome {
        case .permDisabled: 6   // 100/100 absolute trigger
        case .tempDisabled: 5   // 100/100 absolute trigger
        case .success: 4        // Secondary logic
        case .noAccount: 3      // Secondary logic
        case .smsVerification: 2
        case .incorrectPassword: 1
        case .errorBanner: 1
        case .unknown: 0
        }
    }

    /// Produces a paired OCR status string from two site results, matching the
    /// Apple Vision Blueprint's plural vs split definition logic.
    /// If both sites match → pluralize (e.g. "Successes"). Otherwise → "Joe / Ign".
    static func pairedOCRStatus(joe: DetectedOutcome, ignition: DetectedOutcome) -> String {
        if joe == ignition {
            switch joe {
            case .unknown: return "Unsure"
            default: return joe.pairedLabel + "s"
            }
        }
        return "\(joe.pairedLabel) / \(ignition.pairedLabel)"
    }
}
