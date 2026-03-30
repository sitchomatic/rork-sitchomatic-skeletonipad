import Foundation
import WebKit

@MainActor
class PageReadinessService {
    static let shared = PageReadinessService()

    private let logger = DebugLogger.shared
    private let settlement = SmartPageSettlementService.shared
    private let buttonRecovery = SmartButtonRecoveryService.shared

    static let guaranteeBufferSeconds: Double = 1.0

    private let fullReadinessJS = """
    (function() {
        var m = window.__settlementMonitor;
        var now = Date.now();
        var pendingNet = 0;
        var netIdleMs = 9999;
        var domIdleMs = 9999;
        if (m) {
            pendingNet = m.pendingXHR + m.pendingFetch;
            netIdleMs = pendingNet === 0 ? (now - m.lastNetworkActivityMs) : 0;
            domIdleMs = now - m.lastDOMMutationMs;
        }
        var animCount = 0;
        try { animCount = document.getAnimations ? document.getAnimations().length : 0; } catch(e) {}
        var readyState = document.readyState;

        var emailField = document.querySelector('#email')
            || document.querySelector('input[type="email"]')
            || document.querySelector('input[name="email"]')
            || document.querySelector('input[name="username"]')
            || document.querySelector('input[type="text"]');
        var passField = document.querySelector('#login-password')
            || document.querySelector('input[type="password"]');
        var formReady = false;
        if (emailField && passField) {
            var eStyle = window.getComputedStyle(emailField);
            var pStyle = window.getComputedStyle(passField);
            var eVisible = emailField.offsetParent !== null && eStyle.display !== 'none' && eStyle.visibility !== 'hidden';
            var pVisible = passField.offsetParent !== null && pStyle.display !== 'none' && pStyle.visibility !== 'hidden';
            formReady = eVisible && pVisible && !emailField.disabled && !passField.disabled;
        }

        var loginTerms = ['log in','login','sign in','signin'];
        var btns = document.querySelectorAll('button, input[type="submit"], a.btn, [role="button"], #login-submit');
        var btn = document.querySelector('#login-submit');
        if (!btn) {
            for (var i = 0; i < btns.length; i++) {
                var text = (btns[i].textContent || btns[i].value || '').replace(/[\\s]+/g,' ').toLowerCase().trim();
                if (text.length > 50) continue;
                for (var t = 0; t < loginTerms.length; t++) {
                    if (text === loginTerms[t] || (text.indexOf(loginTerms[t]) !== -1 && text.length < 25)) { btn = btns[i]; break; }
                }
                if (btn) break;
            }
        }
        if (!btn) btn = document.querySelector('button[type="submit"]') || document.querySelector('input[type="submit"]');

        var btnReady = false;
        var btnBgColor = '';
        var btnOpacity = 1.0;
        var btnDisabled = false;
        var btnPointer = 'auto';
        var btnCursor = '';
        var hasSpinner = false;
        var hasOverlay = false;

        if (btn) {
            var style = window.getComputedStyle(btn);
            btnBgColor = style.backgroundColor;
            btnOpacity = parseFloat(style.opacity);
            btnDisabled = btn.disabled || false;
            btnPointer = style.pointerEvents;
            btnCursor = style.cursor;

            var spinners = document.querySelectorAll('.spinner, .loading, [class*="spinner"], [class*="loading"], [class*="loader"]');
            for (var s = 0; s < spinners.length; s++) {
                if (spinners[s].offsetParent !== null) { hasSpinner = true; break; }
            }
            var overlays = document.querySelectorAll('.overlay, .modal-backdrop, [class*="overlay"]');
            for (var o = 0; o < overlays.length; o++) {
                if (overlays[o].offsetParent !== null && window.getComputedStyle(overlays[o]).opacity !== '0') { hasOverlay = true; break; }
            }

            btnReady = btnOpacity > 0.7 && !btnDisabled && btnPointer !== 'none'
                && btnCursor !== 'wait' && btnCursor !== 'progress'
                && !hasSpinner && !hasOverlay;
        }

        var jsSettled = readyState === 'complete' && pendingNet === 0 && netIdleMs >= 500 && domIdleMs >= 400 && animCount === 0;

        return JSON.stringify({
            readyState: readyState,
            pendingNet: pendingNet,
            netIdleMs: netIdleMs,
            domIdleMs: domIdleMs,
            animCount: animCount,
            formReady: formReady,
            btnReady: btnReady,
            btnBgColor: btnBgColor,
            btnOpacity: btnOpacity,
            btnDisabled: btnDisabled,
            btnPointer: btnPointer,
            btnCursor: btnCursor,
            hasSpinner: hasSpinner,
            hasOverlay: hasOverlay,
            jsSettled: jsSettled,
            allReady: jsSettled && formReady && btnReady
        });
    })();
    """

    struct ReadinessResult {
        let ready: Bool
        let durationMs: Int
        let reason: String
        let jsSettled: Bool
        let formReady: Bool
        let buttonReady: Bool
    }

    func waitForFullPageReadiness(
        executeJS: @escaping (String) async -> String?,
        host: String,
        sessionId: String,
        maxTimeoutMs: Int = 30000
    ) async -> ReadinessResult {
        let start = Date()

        logger.log("PageReadiness: waiting for full readiness on \(host) (max \(maxTimeoutMs)ms + 1s buffer)", category: .automation, level: .trace, sessionId: sessionId)

        var lastJsSettled = false
        var lastFormReady = false
        var lastBtnReady = false
        var stableCount = 0
        let requiredStableChecks = 3

        while true {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= maxTimeoutMs {
                logger.log("PageReadiness: TIMEOUT after \(elapsedMs)ms — proceeding with 1s buffer", category: .automation, level: .warning, sessionId: sessionId)
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ReadinessResult(ready: false, durationMs: finalMs, reason: "Timeout after \(elapsedMs)ms (js:\(lastJsSettled) form:\(lastFormReady) btn:\(lastBtnReady))", jsSettled: lastJsSettled, formReady: lastFormReady, buttonReady: lastBtnReady)
            }

            guard let raw = await executeJS(fullReadinessJS),
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }

            let jsSettled = json["jsSettled"] as? Bool ?? false
            let formReady = json["formReady"] as? Bool ?? false
            let btnReady = json["btnReady"] as? Bool ?? false
            let allReady = json["allReady"] as? Bool ?? false

            lastJsSettled = jsSettled
            lastFormReady = formReady
            lastBtnReady = btnReady

            if allReady {
                stableCount += 1
            } else {
                stableCount = 0
            }

            if stableCount >= requiredStableChecks {
                let settledMs = Int(Date().timeIntervalSince(start) * 1000)
                logger.log("PageReadiness: all signals GREEN at \(settledMs)ms — adding 1s guarantee buffer", category: .automation, level: .success, sessionId: sessionId)
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ReadinessResult(ready: true, durationMs: finalMs, reason: "All ready (js+form+button settled at \(settledMs)ms + 1s buffer)", jsSettled: true, formReady: true, buttonReady: true)
            }

            if elapsedMs > 8000 && formReady && jsSettled {
                let settledMs = Int(Date().timeIntervalSince(start) * 1000)
                logger.log("PageReadiness: JS+form ready at \(settledMs)ms (button uncertain) — adding 1s buffer", category: .automation, level: .info, sessionId: sessionId)
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ReadinessResult(ready: true, durationMs: finalMs, reason: "JS+form settled at \(settledMs)ms + 1s buffer (button uncertain)", jsSettled: true, formReady: true, buttonReady: btnReady)
            }

            if elapsedMs > 12000 && formReady {
                let settledMs = Int(Date().timeIntervalSince(start) * 1000)
                logger.log("PageReadiness: form ready at \(settledMs)ms — proceeding with 1s buffer", category: .automation, level: .info, sessionId: sessionId)
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ReadinessResult(ready: true, durationMs: finalMs, reason: "Form ready at \(settledMs)ms + 1s buffer", jsSettled: jsSettled, formReady: true, buttonReady: btnReady)
            }

            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    struct ButtonReadyResult {
        let ready: Bool
        let durationMs: Int
        let reason: String
        let recoveredFromFingerprint: Bool
    }

    func waitForButtonReadyForNextAttempt(
        executeJS: @escaping (String) async -> String?,
        originalFingerprint: SmartButtonRecoveryService.ButtonFingerprint?,
        host: String,
        sessionId: String,
        maxTimeoutMs: Int = 25000
    ) async -> ButtonReadyResult {
        let start = Date()

        logger.log("PageReadiness: waiting for button ready on \(host) (max \(maxTimeoutMs)ms + 1s buffer)", category: .automation, level: .trace, sessionId: sessionId)

        if let fingerprint = originalFingerprint {
            let recoveryResult = await buttonRecovery.waitForRecovery(
                originalFingerprint: fingerprint,
                executeJS: executeJS,
                host: host,
                sessionId: sessionId,
                maxTimeoutMs: maxTimeoutMs
            )

            if recoveryResult.recovered {
                logger.log("PageReadiness: button fingerprint recovered in \(recoveryResult.durationMs)ms — now checking JS settlement + 1s buffer", category: .automation, level: .success, sessionId: sessionId)
                let jsReady = await waitForJSSettlement(executeJS: executeJS, sessionId: sessionId, maxTimeoutMs: 10000)
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ButtonReadyResult(ready: true, durationMs: finalMs, reason: "Button recovered in \(recoveryResult.durationMs)ms, JS \(jsReady ? "settled" : "timeout") + 1s buffer", recoveredFromFingerprint: true)
            } else {
                logger.log("PageReadiness: button fingerprint recovery TIMEOUT — falling back to readiness poll", category: .automation, level: .warning, sessionId: sessionId)
            }
        }

        let remainingMs = maxTimeoutMs - Int(Date().timeIntervalSince(start) * 1000)
        if remainingMs > 0 {
            let readiness = await waitForButtonClickable(executeJS: executeJS, sessionId: sessionId, maxTimeoutMs: max(remainingMs, 5000))
            if readiness {
                try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
                let finalMs = Int(Date().timeIntervalSince(start) * 1000)
                return ButtonReadyResult(ready: true, durationMs: finalMs, reason: "Button clickable + JS settled + 1s buffer", recoveredFromFingerprint: false)
            }
        }

        try? await Task.sleep(for: .seconds(Self.guaranteeBufferSeconds))
        let finalMs = Int(Date().timeIntervalSince(start) * 1000)
        return ButtonReadyResult(ready: false, durationMs: finalMs, reason: "Timeout — proceeding with 1s buffer", recoveredFromFingerprint: false)
    }

    private func waitForJSSettlement(executeJS: @escaping (String) async -> String?, sessionId: String, maxTimeoutMs: Int = 10000) async -> Bool {
        let start = Date()
        var stableCount = 0

        let jsCheckScript = """
        (function() {
            var m = window.__settlementMonitor;
            if (!m) return JSON.stringify({settled: false, noMonitor: true});
            var now = Date.now();
            var pendingNet = m.pendingXHR + m.pendingFetch;
            var netIdleMs = pendingNet === 0 ? (now - m.lastNetworkActivityMs) : 0;
            var domIdleMs = now - m.lastDOMMutationMs;
            var animCount = 0;
            try { animCount = document.getAnimations ? document.getAnimations().length : 0; } catch(e) {}
            var settled = document.readyState === 'complete' && pendingNet === 0 && netIdleMs >= 500 && domIdleMs >= 400 && animCount === 0;
            return JSON.stringify({settled: settled, pendingNet: pendingNet, netIdleMs: netIdleMs, domIdleMs: domIdleMs, animCount: animCount});
        })();
        """

        while true {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= maxTimeoutMs { return false }

            guard let raw = await executeJS(jsCheckScript),
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }

            let settled = json["settled"] as? Bool ?? false
            if settled {
                stableCount += 1
                if stableCount >= 2 { return true }
            } else {
                stableCount = 0
            }

            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func waitForButtonClickable(executeJS: @escaping (String) async -> String?, sessionId: String, maxTimeoutMs: Int = 10000) async -> Bool {
        let start = Date()

        let btnCheckJS = """
        (function() {
            var loginTerms = ['log in','login','sign in','signin'];
            var btns = document.querySelectorAll('button, input[type="submit"], a.btn, [role="button"], #login-submit');
            var btn = document.querySelector('#login-submit');
            if (!btn) {
                for (var i = 0; i < btns.length; i++) {
                    var text = (btns[i].textContent || btns[i].value || '').replace(/[\\s]+/g,' ').toLowerCase().trim();
                    if (text.length > 50) continue;
                    for (var t = 0; t < loginTerms.length; t++) {
                        if (text === loginTerms[t] || (text.indexOf(loginTerms[t]) !== -1 && text.length < 25)) { btn = btns[i]; break; }
                    }
                    if (btn) break;
                }
            }
            if (!btn) btn = document.querySelector('button[type="submit"]') || document.querySelector('input[type="submit"]');
            if (!btn) return JSON.stringify({found: false});
            var style = window.getComputedStyle(btn);
            var opacity = parseFloat(style.opacity);
            var disabled = btn.disabled || false;
            var pointer = style.pointerEvents;
            var cursor = style.cursor;
            var spinners = document.querySelectorAll('.spinner, .loading, [class*="spinner"], [class*="loading"], [class*="loader"]');
            var hasSpinner = false;
            for (var s = 0; s < spinners.length; s++) {
                if (spinners[s].offsetParent !== null) { hasSpinner = true; break; }
            }
            var clickable = opacity > 0.7 && !disabled && pointer !== 'none' && cursor !== 'wait' && cursor !== 'progress' && !hasSpinner;
            return JSON.stringify({found: true, clickable: clickable, opacity: opacity, disabled: disabled});
        })();
        """

        var stableCount = 0
        while true {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= maxTimeoutMs { return false }

            guard let raw = await executeJS(btnCheckJS),
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = json["found"] as? Bool, found else {
                try? await Task.sleep(for: .milliseconds(300))
                continue
            }

            let clickable = json["clickable"] as? Bool ?? false
            if clickable {
                stableCount += 1
                if stableCount >= 2 { return true }
            } else {
                stableCount = 0
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
