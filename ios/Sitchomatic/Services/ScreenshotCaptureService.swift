import Foundation
import UIKit

@MainActor
class ScreenshotCaptureService {
    nonisolated(unsafe) static let shared = ScreenshotCaptureService()

    static let proMaxWidth: CGFloat = 1320
    static let proMaxHeight: CGFloat = 2868
    static let defaultCompressionQuality: CGFloat = 0.15
    static let maxStoredScreenshots: Int = 200

    private let logger = DebugLogger.shared

    struct CaptureResult {
        let fullImageData: Data?
        let croppedImageData: Data?
        let rawImage: UIImage?
    }

    func captureAndCompress(from session: some ScreenshotCapableSession, cropRect: CGRect? = nil) async -> CaptureResult {
        guard let rawImage = await session.captureScreenshot() else {
            return CaptureResult(fullImageData: nil, croppedImageData: nil, rawImage: nil)
        }
        return compress(image: rawImage, cropRect: cropRect)
    }

    func compress(image: UIImage, cropRect: CGRect? = nil) -> CaptureResult {
        let scaled = scaleToProMax(image)
        let fullData = scaled.jpegData(compressionQuality: Self.defaultCompressionQuality)

        var croppedData: Data?
        if let cropRect, cropRect != .zero, let cgImage = scaled.cgImage {
            let scaleX = scaled.size.width / image.size.width
            let scaleY = scaled.size.height / image.size.height
            let scaledRect = CGRect(
                x: cropRect.origin.x * scaleX,
                y: cropRect.origin.y * scaleY,
                width: cropRect.width * scaleX,
                height: cropRect.height * scaleY
            )
            let clampedRect = scaledRect.intersection(CGRect(origin: .zero, size: scaled.size))
            if !clampedRect.isEmpty, let cropped = cgImage.cropping(to: clampedRect) {
                let croppedImage = UIImage(cgImage: cropped, scale: scaled.scale, orientation: scaled.imageOrientation)
                croppedData = croppedImage.jpegData(compressionQuality: Self.defaultCompressionQuality)
            }
        }

        return CaptureResult(fullImageData: fullData, croppedImageData: croppedData, rawImage: scaled)
    }

    func compressImageToData(_ image: UIImage) -> Data? {
        let scaled = scaleToProMax(image)
        return scaled.jpegData(compressionQuality: Self.defaultCompressionQuality)
    }

    private func scaleToProMax(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: Self.proMaxWidth, height: Self.proMaxHeight)
        let imageSize = image.size

        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        if imageSize.width == targetSize.width && imageSize.height == targetSize.height {
            return image
        }

        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))

            let origin = CGPoint(
                x: (targetSize.width - newSize.width) / 2,
                y: (targetSize.height - newSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}
