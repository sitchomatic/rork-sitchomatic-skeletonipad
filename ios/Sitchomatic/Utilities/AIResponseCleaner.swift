import Foundation

/// Strips markdown code fences from AI-generated JSON responses.
///
/// Used across all AI services that parse structured JSON from Grok/LLM responses.
/// Centralizes the ``\`\`\`json`` / ``\`\`\``` removal pattern previously duplicated in 17+ files.
nonisolated enum AIResponseCleaner {
    /// Removes markdown code fences and trims whitespace from an AI response string.
    static func cleanJSON(_ response: String) -> String {
        response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
