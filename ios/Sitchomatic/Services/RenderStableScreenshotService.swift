import Foundation
import WebKit
import UIKit

@MainActor
class RenderStableScreenshotService {
    nonisolated(unsafe) static let shared = RenderStableScreenshotService()

    private let logger = DebugLogger.shared
    private let maxStabilityChecks: Int = 6
    private let stabilityCheckIntervalMs: Int = 300
    private let pixelDiffThreshold: Double = 0.02

    func captureStableScreenshotFast(from webView: WKWebView?) async -> UIImage? {
        let profile = DeviceCapability.performanceProfile
        return await captureStableScreenshot(
            from: webView,
            maxChecks: profile.automationStabilityChecks,
            checkIntervalMs: 200
        )
    }

    func captureStableScreenshot(from webView: WKWebView?, fallbackTimeout: TimeInterval = 3.0, maxChecks: Int? = nil, checkIntervalMs: Int? = nil) async -> UIImage? {
        guard let webView else { return nil }
        let needsResize = webView.bounds.width < 2 || webView.bounds.height < 2
        let savedFrame = webView.frame
        if needsResize {
            webView.frame = CGRect(origin: savedFrame.origin, size: CGSize(width: 390, height: 844))
            webView.layoutIfNeeded()
        }
        defer {
            if needsResize { webView.frame = savedFrame }
        }
        guard !webView.isLoading || webView.url != nil else {
            return await directCapture(webView)
        }

        let readyState = try? await webView.evaluateJavaScript("document.readyState") as? String
        if readyState == nil {
            logger.log("RenderStable: readyState JS returned nil — falling back to direct capture", category: .screenshot, level: .debug)
            return await directCapture(webView)
        }
        if readyState != "complete" {
            let start = Date()
            var reachedComplete = false
            while Date().timeIntervalSince(start) < 2.0 {
                let state = try? await webView.evaluateJavaScript("document.readyState") as? String
                if state == "complete" { reachedComplete = true; break }
                if state == nil {
                    logger.log("RenderStable: readyState poll returned nil — falling back to direct capture", category: .screenshot, level: .debug)
                    return await directCapture(webView)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if !reachedComplete {
                logger.log("RenderStable: readyState timeout — proceeding with capture anyway", category: .screenshot, level: .debug)
            }
        }

        let pendingJS = """
        (function(){
            var imgs = document.querySelectorAll('img');
            var pending = 0;
            for (var i = 0; i < imgs.length; i++) {
                if (!imgs[i].complete && imgs[i].src) pending++;
            }
            return pending;
        })()
        """
        if let pendingCount = try? await webView.evaluateJavaScript(pendingJS) as? Int, pendingCount > 0 {
            try? await Task.sleep(for: .milliseconds(500))
        }

        var previousHash: Int?
        var stableCount = 0
        var lastGoodSnapshot: UIImage?

        let checksToRun = maxChecks ?? maxStabilityChecks
        let intervalMs = checkIntervalMs ?? stabilityCheckIntervalMs

        for check in 0..<checksToRun {
            guard webView.bounds.width > 0, webView.bounds.height > 0 else { break }
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            let snapshot: UIImage?
            do {
                snapshot = try await webView.takeSnapshot(configuration: config)
            } catch {
                logger.log("RenderStable: takeSnapshot failed (check \(check)): \(error.localizedDescription)", category: .screenshot, level: .debug)
                break
            }
            guard let snapshot else {
                try? await Task.sleep(for: .milliseconds(intervalMs))
                continue
            }

            lastGoodSnapshot = snapshot
            let currentHash = fastImageHash(snapshot)

            if let prev = previousHash {
                if currentHash == prev {
                    stableCount += 1
                    if stableCount >= 2 {
                        logger.log("RenderStable: stable after \(check + 1) checks", category: .screenshot, level: .trace)
                        return snapshot
                    }
                } else {
                    stableCount = 0
                }
            }

            previousHash = currentHash

            if check == checksToRun - 1 {
                logger.log("RenderStable: returning after max checks (may not be fully stable)", category: .screenshot, level: .debug)
                return snapshot
            }

            try? await Task.sleep(for: .milliseconds(intervalMs))
        }

        if let lastGoodSnapshot {
            logger.log("RenderStable: returning last good snapshot from stability loop", category: .screenshot, level: .debug)
            return lastGoodSnapshot
        }

        return await directCapture(webView)
    }

    private func directCapture(_ webView: WKWebView) async -> UIImage? {
        guard webView.bounds.width > 1, webView.bounds.height > 1 else {
            logger.log("RenderStable: directCapture skipped — bounds too small (\(webView.bounds.size))", category: .screenshot, level: .warning)
            return nil
        }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        do {
            let img = try await webView.takeSnapshot(configuration: config)
            logger.log("RenderStable: direct capture succeeded", category: .screenshot, level: .debug)
            return img
        } catch {
            logger.log("RenderStable: direct capture FAILED: \(error.localizedDescription)", category: .screenshot, level: .warning)
            return nil
        }
    }

    private func fastImageHash(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 16
        let height = 16
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash = 0
        for i in stride(from: 0, to: pixels.count - 1, by: 2) {
            hash = hash &* 31 &+ Int(pixels[i] > pixels[i + 1] ? 1 : 0)
        }
        return hash
    }
}
