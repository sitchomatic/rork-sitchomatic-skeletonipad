import Foundation
import Observation
import UIKit
import SwiftUI

@Observable
@MainActor
class UnifiedScreenshotManager {
    nonisolated(unsafe) static let shared = UnifiedScreenshotManager()

    var screenshots: [UnifiedScreenshot] = []
    var analysisStats: AnalysisStats = AnalysisStats()
    private let maxScreenshots: Int = 300
    private let visionCrop = VisionTextCropService.shared
    private let dedup = ScreenshotDedupService.shared
    private let logger = DebugLogger.shared

    struct AnalysisStats {
        var totalCaptured: Int = 0
        var totalAnalyzed: Int = 0
        var duplicatesSkipped: Int = 0
        var crucialDetections: Int = 0
        var smartCrops: Int = 0
        var outcomeBreakdown: [String: Int] = [:]
    }

    func addScreenshot(
        image: UIImage,
        sessionId: String,
        credentialEmail: String,
        site: String,
        step: ScreenshotStep,
        attemptNumber: Int,
        clickPriority: Int = 0,
        runVisionAnalysis: Bool = true
    ) async {
        analysisStats.totalCaptured += 1

        if dedup.isDuplicate(image) {
            analysisStats.duplicatesSkipped += 1
            logger.log("UnifiedScreenshots: duplicate skipped for \(credentialEmail) step=\(step.rawValue)", category: .screenshot, level: .trace)
            return
        }

        let quality = DeviceCapability.performanceProfile.screenshotCompressionQuality
        let compressedData = await ConcurrentWork.compressImageToData(image, quality: quality, maxDimension: 800)

        let compressedImage: UIImage
        if let data = compressedData, let img = UIImage(data: data) {
            compressedImage = img
        } else {
            compressedImage = image
        }

        var analysis: VisionTextCropService.AnalysisResult?
        var cropResult: VisionTextCropService.CropResult?

        if runVisionAnalysis {
            analysisStats.totalAnalyzed += 1
            let analysisValue = await visionCrop.analyzeScreenshot(compressedImage)
            analysis = analysisValue

            if !analysisValue.crucialMatches.isEmpty {
                analysisStats.crucialDetections += 1
                let crop = await visionCrop.smartCrop(compressedImage, analysis: analysisValue)
                cropResult = crop
                if crop.cropRect != .zero {
                    analysisStats.smartCrops += 1
                }
            }

            let outcomeKey = analysisValue.detectedOutcome.rawValue
            analysisStats.outcomeBreakdown[outcomeKey, default: 0] += 1
        }

        var croppedData: Data?
        if let croppedImg = cropResult?.croppedImage {
            croppedData = await ConcurrentWork.compressImageToData(croppedImg, quality: quality, maxDimension: 800)
        }

        let screenshot = UnifiedScreenshot(
            sessionId: sessionId,
            credentialEmail: credentialEmail,
            site: site,
            step: step,
            attemptNumber: attemptNumber,
            clickPriority: clickPriority,
            fullImageData: compressedData ?? image.jpegData(compressionQuality: 0.4),
            croppedImageData: croppedData,
            detectedOutcome: analysis?.detectedOutcome ?? .unknown,
            crucialKeywords: analysis?.crucialMatches ?? [],
            allDetectedText: analysis?.allText ?? "",
            visionConfidence: analysis?.confidence ?? 0,
            analysisTimeMs: analysis?.processingTimeMs ?? 0
        )

        screenshots.insert(screenshot, at: 0)

        if screenshots.count > maxScreenshots {
            let overflow = screenshots.count - maxScreenshots
            screenshots.removeLast(overflow)
        }

        let crucialInfo = analysis.flatMap { $0.crucialMatches.isEmpty ? nil : " CRUCIAL:\($0.crucialMatches.joined(separator: ","))" } ?? ""
        logger.log("UnifiedScreenshots: captured \(step.rawValue) for \(credentialEmail) site=\(site) attempt=\(attemptNumber)\(crucialInfo)", category: .screenshot, level: crucialInfo.isEmpty ? .debug : .info)
    }

    func screenshotsForSession(_ sessionId: String) -> [UnifiedScreenshot] {
        screenshots.filter { $0.sessionId == sessionId }
    }

    func screenshotsForCredential(_ email: String) -> [UnifiedScreenshot] {
        screenshots.filter { $0.credentialEmail == email }
    }

    func crucialScreenshots() -> [UnifiedScreenshot] {
        screenshots.filter { !$0.crucialKeywords.isEmpty }
    }

    func screenshotsBySite(_ site: String) -> [UnifiedScreenshot] {
        screenshots.filter { $0.site == site }
    }

    func clearAll() {
        let count = screenshots.count
        screenshots.removeAll()
        dedup.resetAll()
        analysisStats = AnalysisStats()
        logger.log("UnifiedScreenshots: cleared \(count) screenshots", category: .screenshot, level: .info)
    }

    func clearForSession(_ sessionId: String) {
        screenshots.removeAll { $0.sessionId == sessionId }
    }

    func smartReduceForClearResult(sessionId: String) {
        let sessionShots = screenshots.filter { $0.sessionId == sessionId }
        guard sessionShots.count > 2 else { return }

        let terminalSteps: Set<ScreenshotStep> = [.terminalState, .successDetected, .crucialResponse, .errorBanner, .smsDetected, .finalState]
        let terminalShots = sessionShots.filter { terminalSteps.contains($0.step) }

        var kept: [UnifiedScreenshot] = []
        let joeFinal = terminalShots.first(where: { $0.site == "joe" }) ?? sessionShots.filter({ $0.site == "joe" }).last
        let ignFinal = terminalShots.first(where: { $0.site == "ignition" }) ?? sessionShots.filter({ $0.site == "ignition" }).last
        if let j = joeFinal { kept.append(j) }
        if let i = ignFinal { kept.append(i) }

        let keepIds = Set(kept.map(\.id))
        let before = screenshots.count
        screenshots.removeAll { $0.sessionId == sessionId && !keepIds.contains($0.id) }
        let removed = before - screenshots.count
        if removed > 0 {
            logger.log("UnifiedScreenshots: smart-reduced to \(kept.count) screenshots (1/site) for clear result — purged \(removed)", category: .screenshot, level: .info)
        }
    }

    func clearNonDisabledForSession(_ sessionId: String) {
        let disabledSteps: Set<ScreenshotStep> = [.terminalState, .crucialResponse]
        let hasDisabled = screenshots.contains { $0.sessionId == sessionId && disabledSteps.contains($0.step) }
        guard hasDisabled else { return }
        let before = screenshots.count
        screenshots.removeAll { $0.sessionId == sessionId && !disabledSteps.contains($0.step) }
        let removed = before - screenshots.count
        if removed > 0 {
            logger.log("UnifiedScreenshots: disabled override — purged \(removed) non-critical screenshots for session", category: .screenshot, level: .info)
        }
    }

    func pruneByPriority(sessionId: String, limit: Int) {
        let sessionShots = screenshots.filter { $0.sessionId == sessionId }
        guard sessionShots.count > limit, limit > 0 else { return }

        let sorted = sessionShots.sorted { $0.clickPriority < $1.clickPriority }
        let toKeepIds = Set(sorted.prefix(limit).map(\.id))
        let before = screenshots.count
        screenshots.removeAll { $0.sessionId == sessionId && !toKeepIds.contains($0.id) }
        let removed = before - screenshots.count
        if removed > 0 {
            logger.log("UnifiedScreenshots: priority pruned \(removed) screenshots (kept \(limit)) for session", category: .screenshot, level: .debug)
        }
    }

    func handleMemoryPressure() {
        let keep = min(screenshots.count, 100)
        if screenshots.count > keep {
            screenshots = Array(screenshots.prefix(keep))
        }
    }

    private func compressImage(_ image: UIImage) -> UIImage {
        if let jpegData = image.jpegData(compressionQuality: 0.4), let compressed = UIImage(data: jpegData) {
            return compressed
        }
        return image
    }

    var totalCompressedDataBytes: Int {
        screenshots.reduce(0) { total, shot in
            total + (shot.fullImageData?.count ?? 0) + (shot.croppedImageData?.count ?? 0)
        }
    }

    var memoryDiagnostic: String {
        let totalKB = totalCompressedDataBytes / 1024
        return "Screenshots: \(screenshots.count) | Data: \(totalKB)KB | Analyzed: \(analysisStats.totalAnalyzed) | Dupes skipped: \(analysisStats.duplicatesSkipped)"
    }
}

@Observable
class UnifiedScreenshot: Identifiable {
    let id: String
    let timestamp: Date
    let sessionId: String
    let credentialEmail: String
    let site: String
    let step: ScreenshotStep
    let attemptNumber: Int
    let fullImageData: Data?
    let croppedImageData: Data?
    let detectedOutcome: VisionTextCropService.DetectedOutcome
    let crucialKeywords: [String]
    let allDetectedText: String
    let visionConfidence: Double
    let analysisTimeMs: Int
    let clickPriority: Int
    var userOverride: UserResultOverride = .none

    private var _cachedFullImage: UIImage?
    private var _cachedCroppedImage: UIImage?

    var fullImage: UIImage {
        if let cached = _cachedFullImage { return cached }
        if let data = fullImageData, let img = UIImage(data: data) {
            _cachedFullImage = img
            return img
        }
        return UIImage()
    }

    var croppedImage: UIImage? {
        if let cached = _cachedCroppedImage { return cached }
        guard let data = croppedImageData, let img = UIImage(data: data) else { return nil }
        _cachedCroppedImage = img
        return img
    }

    var displayImage: UIImage {
        croppedImage ?? fullImage
    }

    var hasCrop: Bool {
        croppedImageData != nil
    }

    var isCrucial: Bool {
        !crucialKeywords.isEmpty
    }

    func evictImageCache() {
        _cachedFullImage = nil
        _cachedCroppedImage = nil
    }

    var outcomeColor: SwiftUI.Color {
        switch detectedOutcome {
        case .success: .green
        case .incorrectPassword, .noAccount: .secondary
        case .permDisabled: .red
        case .tempDisabled: .orange
        case .smsVerification: .purple
        case .errorBanner: .red
        case .unknown: .gray
        }
    }

    var outcomeLabel: String {
        switch detectedOutcome {
        case .success: "SUCCESS"
        case .incorrectPassword: "INCORRECT"
        case .noAccount: "NO ACC"
        case .permDisabled: "PERM DISABLED"
        case .tempDisabled: "TEMP DISABLED"
        case .smsVerification: "SMS"
        case .errorBanner: "ERROR"
        case .unknown: "UNKNOWN"
        }
    }

    var formattedTime: String {
        DateFormatters.timeOnly.string(from: timestamp)
    }

    init(
        sessionId: String,
        credentialEmail: String,
        site: String,
        step: ScreenshotStep,
        attemptNumber: Int,
        clickPriority: Int = 0,
        fullImageData: Data?,
        croppedImageData: Data?,
        detectedOutcome: VisionTextCropService.DetectedOutcome,
        crucialKeywords: [String],
        allDetectedText: String,
        visionConfidence: Double,
        analysisTimeMs: Int
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.sessionId = sessionId
        self.credentialEmail = credentialEmail
        self.site = site
        self.step = step
        self.attemptNumber = attemptNumber
        self.clickPriority = clickPriority
        self.fullImageData = fullImageData
        self.croppedImageData = croppedImageData
        self.detectedOutcome = detectedOutcome
        self.crucialKeywords = crucialKeywords
        self.allDetectedText = allDetectedText
        self.visionConfidence = visionConfidence
        self.analysisTimeMs = analysisTimeMs
    }

    convenience init(
        sessionId: String,
        credentialEmail: String,
        site: String,
        step: ScreenshotStep,
        attemptNumber: Int,
        clickPriority: Int = 0,
        fullImage: UIImage,
        croppedImage: UIImage?,
        detectedOutcome: VisionTextCropService.DetectedOutcome,
        crucialKeywords: [String],
        allDetectedText: String,
        visionConfidence: Double,
        analysisTimeMs: Int
    ) {
        self.init(
            sessionId: sessionId,
            credentialEmail: credentialEmail,
            site: site,
            step: step,
            attemptNumber: attemptNumber,
            clickPriority: clickPriority,
            fullImageData: fullImage.jpegData(compressionQuality: 0.4),
            croppedImageData: croppedImage?.jpegData(compressionQuality: 0.4),
            detectedOutcome: detectedOutcome,
            crucialKeywords: crucialKeywords,
            allDetectedText: allDetectedText,
            visionConfidence: visionConfidence,
            analysisTimeMs: analysisTimeMs
        )
    }
}

nonisolated enum ScreenshotStep: String, Sendable {
    case pageLoad = "page_load"
    case fieldsDetected = "fields_detected"
    case preTyping = "pre_typing"
    case postTyping = "post_typing"
    case preClick = "pre_click"
    case postClick = "post_click"
    case loadingState = "loading_state"
    case settlementWait = "settlement_wait"
    case responseDetected = "response_detected"
    case crucialResponse = "crucial_response"
    case terminalState = "terminal_state"
    case successDetected = "success_detected"
    case errorBanner = "error_banner"
    case smsDetected = "sms_detected"
    case postAttempt = "post_attempt"
    case finalState = "final_state"
    case recoveryAttempt = "recovery_attempt"
    case blankPage = "blank_page"

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var icon: String {
        switch self {
        case .pageLoad: "globe"
        case .fieldsDetected: "text.cursor"
        case .preTyping: "keyboard"
        case .postTyping: "checkmark.rectangle"
        case .preClick: "hand.tap"
        case .postClick: "hand.tap.fill"
        case .loadingState: "hourglass"
        case .settlementWait: "clock.arrow.circlepath"
        case .responseDetected: "text.magnifyingglass"
        case .crucialResponse: "exclamationmark.triangle.fill"
        case .terminalState: "stop.circle.fill"
        case .successDetected: "checkmark.circle.fill"
        case .errorBanner: "exclamationmark.octagon.fill"
        case .smsDetected: "message.fill"
        case .postAttempt: "arrow.clockwise"
        case .finalState: "flag.checkered"
        case .recoveryAttempt: "arrow.triangle.2.circlepath"
        case .blankPage: "rectangle.dashed"
        }
    }

    var isCritical: Bool {
        switch self {
        case .crucialResponse, .terminalState, .successDetected, .errorBanner, .smsDetected: true
        default: false
        }
    }
}
