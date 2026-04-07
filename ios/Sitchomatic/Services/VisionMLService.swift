import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

@MainActor
class VisionMLService {
    static let shared = VisionMLService()

    private let logger = DebugLogger.shared

    nonisolated struct OCRElement: Sendable {
        let text: String
        let boundingBox: CGRect
        let confidence: Float
        let normalizedCenter: CGPoint

        var pixelCenter: CGPoint {
            CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        }
    }

    nonisolated struct UIElementDetection: Sendable {
        let elements: [OCRElement]
        let inputFields: [OCRElement]
        let buttons: [OCRElement]
        let labels: [OCRElement]
        let imageSize: CGSize
        let processingTimeMs: Int
    }

    nonisolated struct LoginFieldDetection: Sendable {
        let emailField: FieldHit?
        let passwordField: FieldHit?
        let loginButton: FieldHit?
        let allText: [OCRElement]
        let confidence: Double
        let method: String
        let instanceMaskRegions: [MaskedRegion]
        let saliencyHotspots: [CGRect]
        let aiEnhanced: Bool

        init(emailField: FieldHit?, passwordField: FieldHit?, loginButton: FieldHit?, allText: [OCRElement], confidence: Double, method: String, instanceMaskRegions: [MaskedRegion] = [], saliencyHotspots: [CGRect] = [], aiEnhanced: Bool = false) {
            self.emailField = emailField
            self.passwordField = passwordField
            self.loginButton = loginButton
            self.allText = allText
            self.confidence = confidence
            self.method = method
            self.instanceMaskRegions = instanceMaskRegions
            self.saliencyHotspots = saliencyHotspots
            self.aiEnhanced = aiEnhanced
        }
    }

    nonisolated struct FieldHit: Sendable {
        let label: String
        let boundingBox: CGRect
        let pixelCoordinate: CGPoint
        let confidence: Float
        let nearbyText: String?
    }

    nonisolated struct MaskedRegion: Sendable {
        let instanceIndex: Int
        let boundingBox: CGRect
        let pixelArea: Int
        let overlappingText: [String]
        let predictedType: String
    }

    nonisolated struct SaliencyResult: Sendable {
        let hotspots: [CGRect]
        let primaryFocus: CGRect?
        let processingTimeMs: Int
    }

    nonisolated enum DisabledDetectionType: String, Sendable {
        case permDisabled
        case tempDisabled
        case smsDetected
        case none
    }

    func recognizeAllText(in image: UIImage) async -> [OCRElement] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let pixelRect = CGRect(
                x: box.origin.x * imageSize.width,
                y: (1 - box.origin.y - box.height) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            let normalizedCenter = CGPoint(
                x: box.origin.x + box.width / 2,
                y: 1 - (box.origin.y + box.height / 2)
            )
            return OCRElement(text: candidate.string, boundingBox: pixelRect, confidence: candidate.confidence, normalizedCenter: normalizedCenter)
        }
    }

    func detectLoginElements(in image: UIImage, viewportSize: CGSize) async -> LoginFieldDetection {
        LoginFieldDetection(emailField: nil, passwordField: nil, loginButton: nil, allText: [], confidence: 0, method: "deprecated_stub")
    }

    func findTextOnScreen(_ searchText: String, in image: UIImage, viewportSize: CGSize) async -> FieldHit? {
        nil
    }

    func detectSuccessIndicators(in image: UIImage) async -> (welcomeFound: Bool, errorFound: Bool, context: String?) {
        (false, false, nil)
    }

    func detectDisabledAccount(in image: UIImage) async -> (type: DisabledDetectionType, matchedText: String?, allOCRText: String) {
        (.none, nil, "")
    }

    func detectRectangularRegions(in image: UIImage) async -> [CGRect] {
        []
    }

    func detectForegroundInstances(in image: UIImage) async -> [MaskedRegion] {
        []
    }

    func detectSaliency(in image: UIImage) async -> SaliencyResult {
        SaliencyResult(hotspots: [], primaryFocus: nil, processingTimeMs: 0)
    }

    func deepDetectLoginElements(in image: UIImage, viewportSize: CGSize) async -> LoginFieldDetection {
        LoginFieldDetection(emailField: nil, passwordField: nil, loginButton: nil, allText: [], confidence: 0, method: "deprecated_stub")
    }

    func clearSaliencyCache() {
    }

    func buildVisionCalibration(from detection: LoginFieldDetection, forURL url: String) -> LoginCalibrationService.URLCalibration {
        LoginCalibrationService.URLCalibration(
            urlPattern: url,
            emailField: nil,
            passwordField: nil,
            loginButton: nil,
            notes: "Deprecated — AI Vision is primary detection"
        )
    }
}
