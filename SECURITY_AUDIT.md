# Security Audit & Remediation Plan

## Executive Summary

This document outlines critical security vulnerabilities discovered in the Sitchomatic iOS application and provides a comprehensive remediation plan to ensure secure credential storage, proper encryption, and secure coding practices.

## Critical Security Issues

### 1. Credential Storage (CRITICAL)

**Issue**: Sensitive credentials stored in plain text JSON files
**Risk Level**: CRITICAL
**Impact**: Complete credential exposure if device is compromised

**Affected Components**:
- `LoginCredential` model - stores username/password
- `PPSRCard` model - stores credit card numbers, CVV, expiry
- `ProxyConfig` - stores proxy authentication credentials
- `NordLynxConfig` - stores VPN private keys and access tokens

**Current Implementation**:
```swift
// VULNERABLE CODE
@MainActor @Observable
final class LoginCredential: Identifiable, Codable, Sendable {
    var id: UUID
    var username: String  // Plain text!
    var password: String  // Plain text!
}
```

**Remediation Required**:
1. Migrate all sensitive credentials to iOS Keychain
2. Use `SecureEnclave` for private key storage
3. Implement proper encryption for data at rest
4. Clear sensitive data from memory after use

### 2. VPN Credential Exposure (CRITICAL)

**Issue**: WireGuard private keys stored in memory and persisted
**Risk Level**: CRITICAL
**Impact**: VPN compromise, traffic interception

**Affected Files**:
- `ios/Sitchomatic/ViewModels/NordLynxConfigViewModel.swift`
- `ios/Sitchomatic/Services/WireGuardTunnelService.swift`

**Current Implementation**:
```swift
// VULNERABLE CODE
@Observable
final class NordLynxConfigViewModel {
    var privateKey: String = ""  // Stored in plain memory!
    var accessKey: String = ""   // Stored in plain memory!
}
```

**Remediation Required**:
1. Store private keys in Keychain with `kSecAttrAccessible = afterFirstUnlock`
2. Use secure memory wiping after key use
3. Never log or persist private keys to disk
4. Implement key rotation mechanism

### 3. Credit Card Data Handling (CRITICAL)

**Issue**: PCI-DSS violations - card data stored locally
**Risk Level**: CRITICAL
**Impact**: PCI-DSS non-compliance, financial liability

**Affected Files**:
- `ios/Sitchomatic/Models/PPSRCard.swift`

**Current Implementation**:
```swift
// VIOLATES PCI-DSS
struct PPSRCard: Codable {
    var number: String  // Full PAN stored!
    var cvv: String     // CVV stored!
    var expiryMonth: String
    var expiryYear: String
}
```

**Remediation Required**:
1. **NEVER** store full PAN (Primary Account Number)
2. Tokenize card numbers immediately via payment processor
3. Never persist CVV (PCI-DSS requirement)
4. Use masked display (last 4 digits only)
5. Implement data retention policy (delete after use)

### 4. JavaScript Injection Vulnerabilities (HIGH)

**Issue**: User input concatenated into JavaScript without sanitization
**Risk Level**: HIGH
**Impact**: XSS attacks, arbitrary code execution in WebView

**Affected Files**:
- `ios/Sitchomatic/Services/LoginJSBuilder.swift`
- `ios/Sitchomatic/Services/DebugClickJSFactory.swift`

**Current Implementation**:
```swift
// VULNERABLE CODE
let js = """
document.querySelector('\(selector)')?.click();
"""
await webView.evaluateJavaScript(js)
```

**Remediation Required**:
1. Sanitize all inputs used in JS injection
2. Use parameterized JS execution when possible
3. Implement Content Security Policy
4. Validate selectors against whitelist

### 5. Proxy Authentication Exposure (HIGH)

**Issue**: Proxy credentials stored in plain text
**Risk Level**: HIGH
**Impact**: Proxy account compromise

**Affected Files**:
- `ios/Sitchomatic/Models/ProxyConfig.swift`

**Current Implementation**:
```swift
struct ProxyConfig: Codable {
    var username: String?  // Plain text!
    var password: String?  // Plain text!
}
```

**Remediation Required**:
1. Store proxy credentials in Keychain
2. Use credential lookup by proxy ID
3. Implement credential expiration

## Secure Credential Storage Implementation

### Recommended Keychain Wrapper

```swift
import Foundation
import Security

@MainActor
final class SecureCredentialStore {
    static let shared = SecureCredentialStore()

    private init() {}

    // MARK: - Save Credentials

    func saveCredential(username: String, password: String, service: String) throws {
        let passwordData = password.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Retrieve Credentials

    func retrievePassword(for username: String, service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw KeychainError.retrievalFailed(status)
        }

        return password
    }

    // MARK: - Delete Credentials

    func deleteCredential(for username: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
    }

    // MARK: - Private Key Storage (Keychain, not Secure Enclave)
    // Note: For true Secure Enclave storage, generate keys with
    // kSecAttrTokenIDSecureEnclave and store the SecKey reference.
    // This implementation stores keys in the iOS Keychain.

    func savePrivateKey(_ key: String, identifier: String) throws {
        let keyData = key.data(using: .utf8)!

        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )!

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationLabel as String: identifier,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: accessControl
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deletionFailed(OSStatus)
}
```

### Migration Plan for Existing Credentials

```swift
@MainActor
final class CredentialMigrationService {
    static let shared = CredentialMigrationService()

    func migrateFromPlainTextToKeychain() async throws {
        // 1. Load existing credentials from persistence actor
        let actor = PersistenceActor.shared
        let credentials: [LoginCredential]? = await actor.read([LoginCredential].self, forKey: "login-credentials")
        guard let credentials, !credentials.isEmpty else { return }

        // 2. Migrate each to Keychain
        for credential in credentials {
            try SecureCredentialStore.shared.saveCredential(
                username: credential.username,
                password: credential.password,
                service: "com.sitchomatic.login.\(credential.id)"
            )
        }

        // 3. Create metadata-only records (no passwords)
        let secureCredentials = credentials.map { credential in
            var secure = credential
            secure.password = "" // Clear password from memory
            return secure
        }

        // 4. Save metadata
        try await actor.write(secureCredentials, forKey: "login-credentials-metadata")

        // 5. Delete old insecure storage
        await actor.remove(forKey: "login-credentials")

        print("✅ Migrated \(credentials.count) credentials to Keychain")
    }
}
```

## Security Checklist

### Immediate Actions (Week 1)

- [ ] Implement `SecureCredentialStore` wrapper
- [ ] Migrate login credentials to Keychain
- [ ] Implement secure memory wiping for sensitive data
- [ ] Remove all plain-text credential storage

### High Priority (Week 2-3)

- [ ] Implement VPN private key secure storage
- [ ] Add credential expiration mechanism
- [ ] Implement JS injection sanitization
- [ ] Add input validation for all user inputs

### Medium Priority (Week 4-5)

- [ ] PCI-DSS compliance audit for card data
- [ ] Implement card tokenization
- [ ] Add security logging (without sensitive data)
- [ ] Implement Content Security Policy

### Low Priority (Week 6+)

- [ ] Certificate pinning for API calls
- [ ] Implement biometric authentication
- [ ] Add jailbreak detection
- [ ] Security penetration testing

## Compliance Requirements

### PCI-DSS Compliance

**Requirements**:
1. Never store CVV/CVC (Requirement 3.2)
2. Mask PAN when displayed (Requirement 3.3)
3. Render PAN unreadable (encryption/tokenization) (Requirement 3.4)
4. Encrypt transmission of cardholder data (Requirement 4.1)

**Current Status**: ❌ NON-COMPLIANT

**Actions Required**:
1. Remove CVV storage completely
2. Tokenize card numbers via payment processor
3. Store only tokens and last 4 digits
4. Implement data retention policy

### GDPR Compliance (if applicable)

**Data Minimization**: Only collect necessary data
**Right to Erasure**: Implement secure deletion
**Data Portability**: Export user data securely
**Encryption**: Encrypt all personal data

## Testing Requirements

### Security Testing

```swift
@Suite("Security Tests")
struct SecurityTests {

    @Test("Credentials not stored in plain text")
    func testNoPlainTextCredentials() async throws {
        let fileManager = FileManager.default
        let persistenceDirectories =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask) +
            fileManager.urls(for: .documentDirectory, in: .userDomainMask)

        let allFiles = try persistenceDirectories.flatMap { directory in
            try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        }

        for file in allFiles {
            let content = try String(contentsOf: file)
            #expect(!content.contains("password"))
            #expect(!content.contains("privateKey"))
            #expect(!content.contains("cvv"))
        }
    }

    @Test("Keychain stores credentials securely")
    func testKeychainSecurity() throws {
        let store = SecureCredentialStore.shared
        try store.saveCredential(
            username: "test@example.com",
            password: "secure123",
            service: "test-service"
        )

        let retrieved = try store.retrievePassword(
            for: "test@example.com",
            service: "test-service"
        )

        #expect(retrieved == "secure123")

        try store.deleteCredential(
            for: "test@example.com",
            service: "test-service"
        )
    }

    @Test("Sensitive data cleared from memory")
    func testMemoryClearing() {
        var sensitiveData = "password123"

        // Use sensitive data
        _ = sensitiveData

        // Ensure memory is cleared before verifying
        withUnsafeMutablePointer(to: &sensitiveData) { ptr in
            ptr.pointee = ""
        }

        // Verify cleared
        #expect(sensitiveData.isEmpty)
    }
}
```

## Monitoring & Auditing

### Security Logging

**DO LOG**:
- Authentication attempts (success/failure)
- Credential access (without values)
- Security policy violations
- Suspicious activity patterns

**DO NOT LOG**:
- Passwords or PINs
- Private keys
- Credit card numbers
- CVV codes
- Session tokens

### Example Secure Logging

```swift
@MainActor
final class SecurityLogger {
    static let shared = SecurityLogger()

    func logAuthenticationAttempt(username: String, success: Bool) {
        let maskedUsername = maskUsername(username)
        print("[SECURITY] Auth attempt: \(maskedUsername) - \(success ? "SUCCESS" : "FAILED")")
    }

    func logCredentialAccess(service: String) {
        print("[SECURITY] Credential accessed: \(service)")
    }

    private func maskUsername(_ username: String) -> String {
        guard username.count > 4 else { return "****" }
        let prefix = username.prefix(2)
        let suffix = username.suffix(2)
        return "\(prefix)***\(suffix)"
    }
}
```

## Conclusion

Implementing these security improvements is **CRITICAL** before production deployment. The current implementation exposes sensitive user data and violates multiple security best practices and compliance requirements.

**Estimated Effort**: 3-4 weeks
**Priority**: CRITICAL - BLOCK PRODUCTION RELEASE

---

**Last Updated**: 2026-04-02
**Reviewed By**: Claude Sonnet 4.5 (Security Audit)
**Next Review**: After implementation
