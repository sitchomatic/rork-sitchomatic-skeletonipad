import Foundation

@MainActor
class SettlementGateEngine {
    static let shared = SettlementGateEngine()

    private let logger = DebugLogger.shared

    nonisolated struct ButtonColorFingerprint: Sendable {
        let bgColor: String
        let textContent: String
        let opacity: Double
        let disabled: Bool
        let pointerEvents: String
    }

    nonisolated struct SettlementResult: Sendable {
        let settled: Bool
        let durationMs: Int
        let sawLoadingState: Bool
        let errorTextVisible: Bool
        let reason: String
    }

    private let captureButtonColorJS = """
    (function(){
        var loginTerms=['log in','login','sign in','signin'];
        var btn=document.querySelector('#login-submit');
        if(!btn){
            var btns=document.querySelectorAll('button,input[type="submit"],[role="button"]');
            for(var i=0;i<btns.length;i++){
                var txt=(btns[i].textContent||btns[i].value||'').replace(/[\\s]+/g,' ').toLowerCase().trim();
                if(txt.length>50)continue;
                for(var t=0;t<loginTerms.length;t++){
                    if(txt===loginTerms[t]||(txt.indexOf(loginTerms[t])!==-1&&txt.length<25)){btn=btns[i];break;}
                }
                if(btn)break;
            }
        }
        if(!btn)btn=document.querySelector('button[type="submit"]')||document.querySelector('input[type="submit"]');
        if(!btn)return JSON.stringify({found:false});
        var s=window.getComputedStyle(btn);
        return JSON.stringify({
            found:true,
            bgColor:s.backgroundColor,
            textContent:(btn.textContent||btn.value||'').replace(/[\\s]+/g,' ').trim().substring(0,50),
            opacity:parseFloat(s.opacity),
            disabled:btn.disabled||false,
            pointerEvents:s.pointerEvents
        });
    })()
    """

    private let checkErrorTextJS = """
    (function(){
        var body=(document.body?document.body.innerText:'').toLowerCase();
        var errorSelectors=['.error-banner','.alert-danger','.alert-error','.login-error','.notification-error','[role="alert"]'];
        var errorVisible=false;
        for(var i=0;i<errorSelectors.length;i++){
            var el=document.querySelector(errorSelectors[i]);
            if(el&&(el.offsetParent!==null||el.offsetHeight>0)){
                var txt=(el.textContent||'').trim();
                if(txt.length>0){errorVisible=true;break;}
            }
        }
        var hasIncorrect=body.indexOf('incorrect')!==-1||body.indexOf('invalid')!==-1||body.indexOf('wrong')!==-1;
        var hasDisabled=body.indexOf('has been disabled')!==-1;
        var hasTempDisabled=body.indexOf('temporarily disabled')!==-1;
        return JSON.stringify({errorVisible:errorVisible,hasIncorrect:hasIncorrect,hasDisabled:hasDisabled,hasTempDisabled:hasTempDisabled});
    })()
    """

    func capturePreClickFingerprint(
        executeJS: @escaping (String) async -> String?,
        sessionId: String = ""
    ) async -> ButtonColorFingerprint? {
        guard let raw = await executeJS(captureButtonColorJS),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let found = json["found"] as? Bool, found else {
            return nil
        }

        return ButtonColorFingerprint(
            bgColor: json["bgColor"] as? String ?? "",
            textContent: json["textContent"] as? String ?? "",
            opacity: json["opacity"] as? Double ?? 1.0,
            disabled: json["disabled"] as? Bool ?? false,
            pointerEvents: json["pointerEvents"] as? String ?? "auto"
        )
    }

    private let checkURLJS = "(function(){try{return window.location.href||'';}catch(e){return'';}})()"

    private let badRedirectPatterns = ["captcha", "challenge", "verify", "/reset", "error", "403", "blocked", "maintenance", "unavailable", "recaptcha", "hcaptcha", "cloudflare", "access-denied", "forbidden"]
    private let goodRedirectPatterns = ["lobby", "/home", "dashboard", "account", "my-", "welcome", "deposit", "recommended", "last-played", "profile", "balance"]

    private nonisolated func classifyRedirectURL(_ url: String) -> RedirectClassification {
        let lower = url.lowercased()
        for pattern in badRedirectPatterns {
            if lower.contains(pattern) {
                return .bad(pattern: pattern)
            }
        }
        for pattern in goodRedirectPatterns {
            if lower.contains(pattern) {
                return .good(pattern: pattern)
            }
        }
        return .unknown
    }

    nonisolated enum RedirectClassification: Sendable {
        case good(pattern: String)
        case bad(pattern: String)
        case unknown
    }

    private func adaptivePollMs(_ elapsedMs: Int) -> Int {
        if elapsedMs < 2000 { return 150 }
        if elapsedMs < 8000 { return 300 }
        return 500
    }

    func waitForSettlement(
        originalFingerprint: ButtonColorFingerprint,
        executeJS: @escaping (String) async -> String?,
        maxTimeoutMs: Int = 15000,
        preClickURL: String? = nil,
        sessionId: String = ""
    ) async -> SettlementResult {
        let start = Date()
        var sawLoadingState = false
        var loadingDetectedAt: Date?
        let loginURL = preClickURL?.lowercased() ?? ""

        while true {
            guard !Task.isCancelled else {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                return SettlementResult(settled: false, durationMs: ms, sawLoadingState: sawLoadingState, errorTextVisible: false, reason: "Task cancelled")
            }

            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs >= maxTimeoutMs {
                return SettlementResult(settled: true, durationMs: elapsedMs, sawLoadingState: sawLoadingState, errorTextVisible: false, reason: "Timeout — proceeding")
            }

            if !loginURL.isEmpty && elapsedMs > 500 {
                let currentURL = (await executeJS(checkURLJS) ?? "").lowercased()
                if !currentURL.isEmpty && currentURL != loginURL && !currentURL.contains("/login") && !currentURL.contains("overlay=login") && currentURL != "about:blank" {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    let classification = classifyRedirectURL(currentURL)
                    switch classification {
                    case .bad(let pattern):
                        logger.log("Settlement: URL redirected to BAD destination in \(ms)ms — matched '\(pattern)' in \(currentURL.prefix(80)) — continuing poll", category: .automation, level: .warning, sessionId: sessionId)
                    case .good(let pattern):
                        logger.log("Settlement: URL redirected to GOOD destination in \(ms)ms — matched '\(pattern)' in \(currentURL.prefix(80))", category: .automation, level: .success, sessionId: sessionId)
                        return SettlementResult(settled: true, durationMs: ms, sawLoadingState: sawLoadingState, errorTextVisible: false, reason: "URL redirected to verified destination (\(pattern))")
                    case .unknown:
                        logger.log("Settlement: URL redirected to UNKNOWN destination in \(ms)ms — \(currentURL.prefix(80)) — treating as settled", category: .automation, level: .warning, sessionId: sessionId)
                        return SettlementResult(settled: true, durationMs: ms, sawLoadingState: sawLoadingState, errorTextVisible: false, reason: "URL redirected to unclassified destination")
                    }
                }
            }

            guard let raw = await executeJS(captureButtonColorJS),
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = json["found"] as? Bool, found else {
                let pollMs = adaptivePollMs(elapsedMs)
                try? await Task.sleep(for: .milliseconds(pollMs))
                continue
            }

            let currentBg = json["bgColor"] as? String ?? ""
            let currentOpacity = json["opacity"] as? Double ?? 1.0
            let currentDisabled = json["disabled"] as? Bool ?? false
            let currentPointer = json["pointerEvents"] as? String ?? "auto"
            let currentText = (json["textContent"] as? String ?? "").lowercased()

            let loadingTerms = ["loading", "please wait", "submitting", "processing", "signing in", "logging in"]
            let isLoading = loadingTerms.contains { currentText.contains($0) }
            let isTranslucent = currentOpacity < 0.7
            let isDisabledState = currentDisabled || currentPointer == "none"
            let colorChanged = currentBg != originalFingerprint.bgColor && !originalFingerprint.bgColor.isEmpty

            if isLoading || isTranslucent || isDisabledState || colorChanged {
                if !sawLoadingState {
                    sawLoadingState = true
                    loadingDetectedAt = Date()
                    logger.log("Settlement: loading state detected — bg:\(colorChanged) opacity:\(isTranslucent) disabled:\(isDisabledState) text:\(isLoading)", category: .automation, level: .trace, sessionId: sessionId)
                }
                try? await Task.sleep(for: .milliseconds(150))
                continue
            }

            if sawLoadingState {
                let bgReverted = currentBg == originalFingerprint.bgColor || originalFingerprint.bgColor.isEmpty
                let opacityReverted = abs(currentOpacity - originalFingerprint.opacity) < 0.15
                let notDisabled = !currentDisabled && currentPointer != "none"

                if bgReverted && opacityReverted && notDisabled {
                    guard let errorRaw = await executeJS(checkErrorTextJS),
                          let errorData = errorRaw.data(using: .utf8),
                          let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any] else {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        return SettlementResult(settled: true, durationMs: ms, sawLoadingState: true, errorTextVisible: false, reason: "Color reverted, error check failed — proceeding")
                    }

                    let errorVisible = errorJson["errorVisible"] as? Bool ?? false
                    let hasIncorrect = errorJson["hasIncorrect"] as? Bool ?? false
                    let hasDisabled = errorJson["hasDisabled"] as? Bool ?? false
                    let hasTempDisabled = errorJson["hasTempDisabled"] as? Bool ?? false

                    if errorVisible || hasIncorrect || hasDisabled || hasTempDisabled {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        logger.log("Settlement: SETTLED in \(ms)ms — color reverted + error/response text visible", category: .automation, level: .success, sessionId: sessionId)
                        return SettlementResult(settled: true, durationMs: ms, sawLoadingState: true, errorTextVisible: true, reason: "Full settlement — color reverted + response visible")
                    }

                    if let loadingStart = loadingDetectedAt,
                       Date().timeIntervalSince(loadingStart) > 3.0 {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        return SettlementResult(settled: true, durationMs: ms, sawLoadingState: true, errorTextVisible: false, reason: "Color reverted after 3s loading — no error text yet, proceeding")
                    }
                }
            }

            if !sawLoadingState && elapsedMs > 800 {
                guard let errorRaw = await executeJS(checkErrorTextJS),
                      let errorData = errorRaw.data(using: .utf8),
                      let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any] else {
                    let pollMs = adaptivePollMs(elapsedMs)
                    try? await Task.sleep(for: .milliseconds(pollMs))
                    continue
                }

                let errorVisible = errorJson["errorVisible"] as? Bool ?? false
                let hasIncorrect = errorJson["hasIncorrect"] as? Bool ?? false
                let hasDisabled = errorJson["hasDisabled"] as? Bool ?? false
                let hasTempDisabled = errorJson["hasTempDisabled"] as? Bool ?? false

                if errorVisible || hasIncorrect || hasDisabled || hasTempDisabled {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    logger.log("Settlement: early error text in \(ms)ms (no loading state)", category: .automation, level: .success, sessionId: sessionId)
                    return SettlementResult(settled: true, durationMs: ms, sawLoadingState: false, errorTextVisible: true, reason: "No loading detected but response text appeared after \(ms)ms")
                }
            }

            let pollMs = adaptivePollMs(elapsedMs)
            try? await Task.sleep(for: .milliseconds(pollMs))
        }
    }
}
