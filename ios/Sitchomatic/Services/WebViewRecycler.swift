import Foundation
@preconcurrency import WebKit

@MainActor
final class WebViewRecycler {
    static let shared = WebViewRecycler()

    private var availableViews: [WKWebView] = []
    private let logger = DebugLogger.shared
    private let poolManager = WebViewProcessPoolManager.shared

    private(set) var totalCheckouts: Int = 0
    private(set) var totalReturns: Int = 0
    private(set) var totalCreatedFresh: Int = 0
    private(set) var totalPrewarmed: Int = 0

    private var maxPoolSize: Int {
        DeviceCapability.performanceProfile.maxRecycledWebViews
    }

    private init() {}

    func prewarm(count: Int? = nil) {
        let target = count ?? DeviceCapability.performanceProfile.webViewPrewarmCount
        let toCreate = min(target, maxPoolSize - availableViews.count)
        guard toCreate > 0 else { return }

        logger.log("WebViewRecycler: pre-warming \(toCreate) views", category: .webView, level: .info)

        for _ in 0..<toCreate {
            let view = createFreshView(viewport: CGSize(width: 390, height: 844))
            availableViews.append(view)
            totalPrewarmed += 1
        }

        logger.log("WebViewRecycler: pre-warm complete — pool size: \(availableViews.count)", category: .webView, level: .info)
    }

    func checkout(viewport: CGSize = CGSize(width: 390, height: 844), pairIndex: Int = 0) -> WKWebView {
        totalCheckouts += 1

        if let recycled = availableViews.popLast() {
            recycled.frame = CGRect(origin: .zero, size: viewport)

            let freshConfig = WKUserContentController()
            recycled.configuration.userContentController = freshConfig

            logger.log("WebViewRecycler: checkout recycled view (pool: \(availableViews.count) remaining)", category: .webView, level: .trace)
            return recycled
        }

        totalCreatedFresh += 1
        let fresh = createFreshView(viewport: viewport, pairIndex: pairIndex)
        logger.log("WebViewRecycler: checkout fresh view (pool empty, total fresh: \(totalCreatedFresh))", category: .webView, level: .debug)
        return fresh
    }

    func returnView(_ webView: WKWebView) {
        totalReturns += 1

        guard availableViews.count < maxPoolSize else {
            destroyView(webView)
            logger.log("WebViewRecycler: pool full — destroyed returned view", category: .webView, level: .debug)
            return
        }

        cleanView(webView)
        availableViews.append(webView)
        logger.log("WebViewRecycler: returned & cleaned (pool: \(availableViews.count))", category: .webView, level: .trace)
    }

    func emergencyFlush() {
        let count = availableViews.count
        for view in availableViews {
            destroyView(view)
        }
        availableViews.removeAll()
        logger.log("WebViewRecycler: EMERGENCY FLUSH — destroyed \(count) pooled views", category: .webView, level: .critical)
    }

    func reset() {
        emergencyFlush()
        totalCheckouts = 0
        totalReturns = 0
        totalCreatedFresh = 0
        totalPrewarmed = 0
    }

    var poolSize: Int { availableViews.count }

    var diagnosticSummary: String {
        "Pool: \(availableViews.count)/\(maxPoolSize) | Checkouts: \(totalCheckouts) | Returns: \(totalReturns) | Fresh: \(totalCreatedFresh) | Prewarmed: \(totalPrewarmed)"
    }

    private func createFreshView(viewport: CGSize, pairIndex: Int = 0) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = poolManager.pool(forPairIndex: pairIndex)
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.suppressesIncrementalRendering = true
        config.userContentController = WKUserContentController()

        let wv = WKWebView(frame: CGRect(origin: .zero, size: viewport), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        return wv
    }

    private func cleanView(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil

        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.removeAllScriptMessageHandlers()

        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}

        webView.configuration.websiteDataStore = .nonPersistent()

        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    }

    private func destroyView(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
}
