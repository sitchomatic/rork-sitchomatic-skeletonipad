import Foundation

nonisolated struct InterventionRecord: Codable, Sendable {
    let host: String
    let pageContentSnippet: String
    let currentURL: String
    let originalClassification: String
    let userCorrectedOutcome: String
    let actionTaken: String
    let timestamp: Date
}

nonisolated struct InterventionPattern: Codable, Sendable {
    var keywords: [String: Int] = [:]
    var urlPatterns: [String: Int] = [:]
    var correctionCount: Int = 0
    var lastUpdated: Date = .distantPast
}

nonisolated struct InterventionLearningStore: Codable, Sendable {
    var records: [InterventionRecord] = []
    var outcomePatterns: [String: InterventionPattern] = [:]
    var autoHealRules: [String: String] = [:]
    var totalCorrections: Int = 0
    var totalAutoHeals: Int = 0
}

@MainActor
class UserInterventionLearningService {
    static let shared = UserInterventionLearningService()

    private var store = InterventionLearningStore()

    func recordCorrection(
        host: String,
        pageContent: String,
        currentURL: String,
        originalClassification: String,
        userCorrectedOutcome: String,
        actionTaken: String
    ) {
    }

    func suggestAutoHeal(host: String, pageContent: String, currentURL: String, currentClassification: String) -> String? {
        nil
    }

    func stats() -> (totalCorrections: Int, totalAutoHeals: Int, uniqueHosts: Int) {
        (store.totalCorrections, store.totalAutoHeals, store.outcomePatterns.count)
    }

    func clearAll() {
        store = InterventionLearningStore()
    }
}
