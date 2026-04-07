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
            textBlocks.append(DetectedTextBlock(text: candidate.string, boundingBox: pixelRect, confidence: candidate.confidence, isCrucial: false))
            allTextParts.append(candidate.string)
        }

        let allText = allTextParts.joined(separator: " ")
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)

        return AnalysisResult(allText: allText, crucialMatches: [], detectedOutcome: .unknown, confidence: 0, textBlocks: textBlocks, processingTimeMs: elapsed)
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

        let allBlocks = analysisResult.textBlocks
        if !allBlocks.isEmpty {
            let textRegion = computeTextBodyBounds(blocks: allBlocks, imageSize: imageSize)
            if let cropped = cropImage(cgImage, to: textRegion, padding: 30, imageSize: imageSize, original: image) {
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                return CropResult(croppedImage: cropped, fullImage: image, detectedTexts: allBlocks, crucialKeywords: [], cropRect: textRegion, processingTimeMs: elapsed)
            }
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        return CropResult(croppedImage: image, fullImage: image, detectedTexts: analysisResult.textBlocks, crucialKeywords: [], cropRect: .zero, processingTimeMs: elapsed)
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
