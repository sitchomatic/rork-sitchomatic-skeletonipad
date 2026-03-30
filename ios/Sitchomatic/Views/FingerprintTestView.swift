import Foundation
import SwiftUI
import WebKit

@Observable
class FPLiveTestSession {
    let id: UUID = UUID()
    let profileSlot: Int
    let profileLabel: String
    var status: FPLiveStatus = .idle
    var suspectText: String = ""
    var fullPageScreenshot: UIImage?
    var focusedScreenshot: UIImage?
    var elapsedMs: Int = 0
    var startedAt: Date?
    var webView: WKWebView?
    var pageTitle: String = ""
    var errorMessage: String = ""

    nonisolated enum FPLiveStatus: String, Sendable {
        case idle = "Idle"
        case loading = "Loading"
        case loaded = "Loaded"
        case screenshotting = "Capturing"
        case complete = "Complete"
        case error = "Error"
    }

    init(profileSlot: Int, profileLabel: String) {
        self.profileSlot = profileSlot
        self.profileLabel = profileLabel
    }
}

class FPLiveNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            onFinished?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            onFailed?(error.localizedDescription)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            onFailed?(error.localizedDescription)
        }
    }
}

struct FingerprintTestView: View {
    @State private var session: FPLiveTestSession?
    @State private var isRunning: Bool = false
    @State private var selectedProfile: Int = 0
    @State private var navDelegate: FPLiveNavigationDelegate?
    @State private var showFullScreenshot: Bool = false

    private let stealth = PPSRStealthService.shared
    private let networkFactory = NetworkSessionFactory.shared
    private let deviceProxy = DeviceProxyService.shared
    private let proxyService = ProxyRotationService.shared
    private let logger = DebugLogger.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileSelector

                launchButton

                if let session {
                    statusCard(session)

                    if let focused = session.focusedScreenshot {
                        screenshotCard(title: "SUSPECT Focus", image: focused, highlight: true)
                    }

                    if let full = session.fullPageScreenshot {
                        screenshotCard(title: "Full Page", image: full, highlight: false)
                    }

                    if !session.suspectText.isEmpty {
                        suspectTextCard(session)
                    }

                    if !session.errorMessage.isEmpty {
                        errorCard(session)
                    }
                }

                if session == nil {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Fingerprint.com Test")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { cleanup() }
        .sheet(isPresented: $showFullScreenshot) {
            if let img = session?.fullPageScreenshot {
                NavigationStack {
                    ScrollView {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding()
                    }
                    .navigationTitle("Full Page Screenshot")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFullScreenshot = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Profile Selector

    private var profileSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stealth Profile", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Profile", selection: $selectedProfile) {
                ForEach(0..<stealth.profileCount, id: \.self) { i in
                    let profile = stealth.profileForSlot(i)
                    Text(profileDescription(profile, slot: i))
                        .tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Launch

    private var launchButton: some View {
        Button {
            if isRunning {
                stopTest()
            } else {
                launchTest()
            }
        } label: {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("LOADING FINGERPRINT.COM...")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                } else {
                    Image(systemName: "fingerprint")
                        .font(.system(size: 16, weight: .bold))
                    Text("LOAD FINGERPRINT.COM")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isRunning
                    ? AnyShapeStyle(.red.opacity(0.8))
                    : AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
            )
            .clipShape(.rect(cornerRadius: 12))
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: isRunning)
    }

    // MARK: - Status Card

    private func statusCard(_ session: FPLiveTestSession) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(statusColor(session.status).opacity(0.12))
                        .frame(width: 44, height: 44)

                    if session.status == .loading || session.status == .screenshotting {
                        ProgressView().controlSize(.small).tint(statusColor(session.status))
                    } else {
                        Image(systemName: statusIcon(session.status))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(statusColor(session.status))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.status.rawValue.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(statusColor(session.status))

                    Text(session.profileLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !session.pageTitle.isEmpty {
                        Text(session.pageTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if session.elapsedMs > 0 {
                    Text("\(session.elapsedMs)ms")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Screenshot Cards

    private func screenshotCard(title: String, image: UIImage, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: highlight ? "scope" : "photo")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(highlight ? .orange : .secondary)

                Spacer()

                if !highlight {
                    Button {
                        showFullScreenshot = true
                    } label: {
                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                }

                Text("\(Int(image.size.width))\u{00D7}\(Int(image.size.height))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(highlight ? .orange.opacity(0.6) : .clear, lineWidth: highlight ? 2 : 0)
                )
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Suspect Text Card

    private func suspectTextCard(_ session: FPLiveTestSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Detected \"suspect\" Context", systemImage: "text.magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)

            Text(session.suspectText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 8))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Error Card

    private func errorCard(_ session: FPLiveTestSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)

            Text(session.errorMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red.opacity(0.8))
        }
        .padding(14)
        .background(.red.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "fingerprint")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            Text("Fingerprint.com Live Test")
                .font(.title2.bold())

            Text("Loads the actual fingerprint.com page in a single\nwebview with your selected stealth profile.\nCaptures a full-page screenshot and a focused\nview around the word \"suspect\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                fpInfoRow(icon: "person.2.fill", label: "Profiles", value: "\(stealth.profileCount)")
                fpInfoRow(icon: "globe", label: "Target", value: "fingerprint.com")
                fpInfoRow(icon: "scope", label: "Focus", value: "\"suspect\" keyword")
                fpInfoRow(icon: "shield.checkered", label: "IP Mode", value: deviceProxy.ipRoutingMode.shortLabel)
                fpInfoRow(icon: "network", label: "Connection", value: proxyService.connectionMode(for: .joe).label)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func fpInfoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
    }

    // MARK: - Test Execution

    private func launchTest() {
        cleanup()

        let profile = stealth.profileForSlot(selectedProfile)
        let label = profileDescription(profile, slot: selectedProfile)
        let testSession = FPLiveTestSession(profileSlot: selectedProfile, profileLabel: label)
        testSession.status = .loading
        testSession.startedAt = Date()
        session = testSession
        isRunning = true

        let wkConfig = WKWebViewConfiguration()
        wkConfig.websiteDataStore = .nonPersistent()
        wkConfig.preferences.javaScriptCanOpenWindowsAutomatically = true
        wkConfig.defaultWebpagePreferences.allowsContentJavaScript = true

        let stealthScript = stealth.createStealthUserScript(profile: profile)
        wkConfig.userContentController.addUserScript(stealthScript)

        let appWideNet = networkFactory.appWideConfig(for: .joe)
        networkFactory.configureWKWebView(config: wkConfig, networkConfig: appWideNet, target: .joe)

        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: CGSize(width: profile.viewport.width, height: profile.viewport.height)),
            configuration: wkConfig
        )
        webView.customUserAgent = profile.userAgent
        testSession.webView = webView

        let delegate = FPLiveNavigationDelegate()
        delegate.onFinished = {
            Task { @MainActor in
                guard let s = self.session, s.id == testSession.id else { return }
                s.status = .loaded
                if let started = s.startedAt {
                    s.elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                }

                let titleJS = "document.title || ''"
                let title = try? await webView.evaluateJavaScript(titleJS) as? String
                s.pageTitle = title ?? ""

                await self.captureScreenshots(session: s, webView: webView)
            }
        }
        delegate.onFailed = { error in
            Task { @MainActor in
                guard let s = self.session, s.id == testSession.id else { return }
                s.status = .error
                s.errorMessage = error
                if let started = s.startedAt {
                    s.elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                }
                self.isRunning = false
                self.logger.log("FingerprintTest: load failed \u{2014} \(error)", category: .fingerprint, level: .error)
            }
        }
        navDelegate = delegate
        webView.navigationDelegate = delegate

        guard let url = URL(string: "https://fingerprint.com/products/bot-detection/") else {
            testSession.status = .error
            testSession.errorMessage = "Invalid URL"
            isRunning = false
            return
        }

        webView.load(URLRequest(url: url))
        logger.log("FingerprintTest: loading fingerprint.com with profile \(label)", category: .fingerprint, level: .info)
    }

    private func captureScreenshots(session: FPLiveTestSession, webView: WKWebView) async {
        session.status = .screenshotting

        try? await Task.sleep(for: .seconds(3))

        let fullConfig = WKSnapshotConfiguration()
        let fullImage: UIImage?
        do {
            fullImage = try await webView.takeSnapshot(configuration: fullConfig)
        } catch {
            session.errorMessage = "Screenshot failed: \(error.localizedDescription)"
            session.status = .error
            isRunning = false
            return
        }
        session.fullPageScreenshot = fullImage

        let suspectJS = """
        (function() {
            var result = { found: false, text: '', rect: null };
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
            var node;
            while (node = walker.nextNode()) {
                var lower = node.textContent.toLowerCase();
                var idx = lower.indexOf('suspect');
                if (idx !== -1) {
                    var range = document.createRange();
                    range.setStart(node, Math.max(0, idx - 20));
                    range.setEnd(node, Math.min(node.textContent.length, idx + 40));
                    var rect = range.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0) {
                        var context = node.textContent.substring(Math.max(0, idx - 50), Math.min(node.textContent.length, idx + 50));
                        result = {
                            found: true,
                            text: context.trim(),
                            rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
                        };
                        break;
                    }
                }
            }
            return JSON.stringify(result);
        })()
        """

        let suspectResult: String?
        do {
            suspectResult = try await webView.evaluateJavaScript(suspectJS) as? String
        } catch {
            suspectResult = nil
        }

        if let jsonString = suspectResult,
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let found = dict["found"] as? Bool, found,
           let text = dict["text"] as? String,
           let rectDict = dict["rect"] as? [String: Double],
           let rx = rectDict["x"], let ry = rectDict["y"],
           let rw = rectDict["width"], let rh = rectDict["height"] {

            session.suspectText = text

            let padding: CGFloat = 80
            let focusRect = CGRect(
                x: max(0, rx - padding),
                y: max(0, ry - padding),
                width: rw + padding * 2,
                height: rh + padding * 2
            )

            let focusConfig = WKSnapshotConfiguration()
            focusConfig.rect = focusRect
            do {
                let focusImage = try await webView.takeSnapshot(configuration: focusConfig)
                session.focusedScreenshot = focusImage
            } catch {
                logger.log("FingerprintTest: focus screenshot failed \u{2014} \(error.localizedDescription)", category: .fingerprint, level: .warning)
            }
        } else {
            session.suspectText = "(word \"suspect\" not found on page)"

            let scrollJS = """
            (function() {
                var all = document.querySelectorAll('h1,h2,h3,p,span,div');
                for (var i = 0; i < all.length; i++) {
                    var t = all[i].textContent.toLowerCase();
                    if (t.indexOf('bot') !== -1 || t.indexOf('detect') !== -1 || t.indexOf('score') !== -1) {
                        var rect = all[i].getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0) {
                            return JSON.stringify({ x: rect.x, y: rect.y, width: rect.width, height: rect.height });
                        }
                    }
                }
                return null;
            })()
            """
            if let altResult = try? await webView.evaluateJavaScript(scrollJS) as? String,
               let altData = altResult.data(using: .utf8),
               let altRect = try? JSONSerialization.jsonObject(with: altData) as? [String: Double],
               let ax = altRect["x"], let ay = altRect["y"],
               let aw = altRect["width"], let ah = altRect["height"] {
                let padding: CGFloat = 60
                let focusConfig = WKSnapshotConfiguration()
                focusConfig.rect = CGRect(x: max(0, ax - padding), y: max(0, ay - padding), width: aw + padding * 2, height: ah + padding * 2)
                if let altImage = try? await webView.takeSnapshot(configuration: focusConfig) {
                    session.focusedScreenshot = altImage
                }
            }
        }

        if let started = session.startedAt {
            session.elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        }
        session.status = .complete
        isRunning = false
        logger.log("FingerprintTest: complete \u{2014} suspect=\"\(session.suspectText.prefix(60))\" elapsed=\(session.elapsedMs)ms", category: .fingerprint, level: .success)
    }

    private func stopTest() {
        cleanup()
        if let s = session {
            s.status = .error
            s.errorMessage = "Stopped by user"
        }
        isRunning = false
        logger.log("FingerprintTest: stopped by user", category: .fingerprint, level: .warning)
    }

    private func cleanup() {
        session?.webView?.stopLoading()
        session?.webView?.navigationDelegate = nil
        session?.webView = nil
        navDelegate = nil
        isRunning = false
    }

    // MARK: - Helpers

    private func profileDescription(_ profile: PPSRStealthService.SessionProfile, slot: Int) -> String {
        let device: String
        let vp = profile.viewport
        switch (vp.width, vp.height) {
        case (440, 956): device = "iPhone 16 Pro Max"
        case (430, 932): device = "iPhone 16 Plus"
        case (402, 874): device = "iPhone 16 Pro"
        case (420, 912): device = "iPhone Air"
        case (393, 852): device = "iPhone 15/16"
        case (390, 844): device = "iPhone 14/13/12"
        case (428, 926): device = "iPhone 13 Pro Max"
        case (834, 1194): device = "iPad Pro 11\""
        case (1440, 900): device = "MacBook Air"
        case (1512, 982): device = "MacBook Pro"
        default: device = "Device \(vp.width)x\(vp.height)"
        }

        let os = profile.userAgent.contains("Version/26.0") ? "iOS 26" :
                 profile.userAgent.contains("18_4") ? "iOS 18.4" :
                 profile.userAgent.contains("18_3") ? "iOS 18.3" :
                 profile.userAgent.contains("18_2") ? "iOS 18.2" :
                 profile.userAgent.contains("18_1") ? "iOS 18.1" :
                 profile.userAgent.contains("17_7") ? "iOS 17.7" :
                 profile.userAgent.contains("17_6") ? "iOS 17.6" :
                 profile.userAgent.contains("17_5") ? "iOS 17.5" :
                 profile.userAgent.contains("17_4") ? "iOS 17.4" :
                 profile.userAgent.contains("14_7") ? "macOS 14.7" :
                 profile.userAgent.contains("10_15") ? "macOS 13.6" :
                 profile.userAgent.contains("OS 18_4") && profile.platform == "iPad" ? "iPadOS 18.4" : "Unknown"

        return "\(device) \u{2022} \(os) \u{2022} \(profile.language)"
    }

    private func statusColor(_ status: FPLiveTestSession.FPLiveStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .loading: .cyan
        case .loaded: .blue
        case .screenshotting: .purple
        case .complete: .green
        case .error: .red
        }
    }

    private func statusIcon(_ status: FPLiveTestSession.FPLiveStatus) -> String {
        switch status {
        case .idle: "circle.dashed"
        case .loading: "globe"
        case .loaded: "checkmark.circle"
        case .screenshotting: "camera.viewfinder"
        case .complete: "checkmark.seal.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}
