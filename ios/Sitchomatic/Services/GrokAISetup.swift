import Foundation

@MainActor
enum GrokAISetup {

    @discardableResult
    static func configure(apiKey: String) -> Bool {
        guard !apiKey.isEmpty else {
            DebugLogger.shared.log("GrokAISetup: empty API key rejected", category: .automation, level: .error)
            return false
        }
        let stored = GrokKeychain.shared.setAPIKey(apiKey)
        if stored {
            DebugLogger.shared.log("GrokAISetup: API key configured ✓", category: .automation, level: .success)
        } else {
            DebugLogger.shared.log("GrokAISetup: failed to store API key in Keychain", category: .automation, level: .error)
        }
        return stored
    }

    @discardableResult
    static func bootstrapFromEnvironment() -> Bool {
        let envKey = Config.EXPO_PUBLIC_GROK_API_KEY
        guard !envKey.isEmpty else {
            DebugLogger.shared.log("GrokAISetup: EXPO_PUBLIC_GROK_API_KEY not set in environment", category: .automation, level: .warning)
            return GrokKeychain.shared.hasAPIKey
        }
        let stored = GrokKeychain.shared.setAPIKey(envKey)
        if stored {
            DebugLogger.shared.log("GrokAISetup: bootstrapped API key from environment ✓", category: .automation, level: .success)
        }
        return stored
    }

    static var isConfigured: Bool {
        GrokKeychain.shared.hasAPIKey
    }

    static func reset() {
        GrokKeychain.shared.removeAPIKey()
        DebugLogger.shared.log("GrokAISetup: API key removed", category: .automation, level: .info)
    }
}
