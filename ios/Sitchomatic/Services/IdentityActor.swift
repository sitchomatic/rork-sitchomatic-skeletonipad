// IdentityActor.swift
// rork-Sitchomatic-APEX
//
// "Burn & Rotate" Security Protocol.
// When a WebView detects an SMS 2FA or Challenge string the actor
// triggers session data wipe, IP rotation, and UUID scramble
// before retrying the credential.

import Foundation
@preconcurrency import WebKit

/// Centralised identity-rotation actor.
/// Thread-safe, non-MainActor so it can be called from any
/// automation context (SitchomaticApexActor or MainActor).
actor IdentityActor {
    static let shared = IdentityActor()

    // MARK: - Fingerprint-Detection Keywords

    /// Strings whose presence in page content signals a fingerprint
    /// detection event (SMS 2FA, challenge page, CAPTCHA gate).
    static let fingerprintKeywords: [String] = [
        "sms", "text message", "verification code", "verify your phone",
        "send code", "sent a code", "enter the code", "phone verification",
        "mobile verification", "confirm your number", "code sent",
        "enter code", "security code sent", "check your phone",
        "two-factor", "2fa", "two factor", "challenge"
    ]

    // MARK: - Detection

    /// Returns `true` when `content` contains any fingerprint keyword.
    func isFingerprintDetected(in content: String) -> Bool {
        let lower = content.lowercased()
        return Self.fingerprintKeywords.contains { lower.contains($0) }
    }

    // MARK: - Burn & Rotate

    /// Full burn-and-rotate sequence for a given non-persistent data store.
    ///
    /// 1. Wipe all website data for the session.
    /// 2. Rotate IP via the proxy service.
    /// 3. Scramble device metrics (hardware UUID façade).
    ///
    /// Call this from @MainActor context since WKWebsiteDataStore
    /// operations require it.
    @MainActor
    func burnAndRotate(
        dataStore: WKWebsiteDataStore,
        proxyTarget: ProxyRotationService.ProxyTarget
    ) async {
        let logger = DebugLogger.shared

        // 1. Wipe session data
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: allTypes, modifiedSince: .distantPast)
        logger.log("IdentityActor: session data burned", category: .network, level: .warning)

        // 2. IP rotation via proxy service
        await ProxyRotationService.shared.rotateProxy(for: proxyTarget)
        logger.log("IdentityActor: IP rotated for \(proxyTarget.rawValue)", category: .network, level: .warning)

        // 3. Scramble hardware UUID metrics
        scrambleDeviceMetrics()
        logger.log("IdentityActor: hardware UUID metrics scrambled", category: .fingerprint, level: .warning)
    }

    // MARK: - UUID Scramble

    /// Produces a fresh pseudo-random device-metric façade that
    /// stealth scripts will inject on the next page load.
    private nonisolated func scrambleDeviceMetrics() {
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: "apex_scrambled_hw_uuid")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "apex_uuid_scramble_ts")
    }
}
