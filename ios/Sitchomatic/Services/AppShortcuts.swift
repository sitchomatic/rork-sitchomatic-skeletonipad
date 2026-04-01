import Foundation
import AppIntents
import SwiftUI

nonisolated struct CheckStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Stats"
    static let description: IntentDescription = "View current card and credential statistics"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stats = StatsTrackingService.shared
        let tested = await stats.lifetimeTested
        let working = await stats.lifetimeWorking
        let dead = await stats.lifetimeDead
        let rate = await stats.lifetimeSuccessRate

        let message = "Lifetime: \(tested) tested, \(working) working, \(dead) dead. Success rate: \(String(format: "%.0f%%", rate * 100))."
        return .result(dialog: "\(message)")
    }
}

nonisolated struct OpenPPSRModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PPSR Mode"
    static let description: IntentDescription = "Open the PPSR card testing mode"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("ppsr", forKey: "activeAppMode")
        return .result()
    }
}

nonisolated struct OpenLoginTestingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Login Testing"
    static let description: IntentDescription = "Open the unified login testing mode (JoePoint + Ignition)"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("unifiedSession", forKey: "activeAppMode")
        return .result()
    }
}

nonisolated struct OpenNordConfigIntent: AppIntent {
    static let title: LocalizedStringResource = "Open NordLynx Config"
    static let description: IntentDescription = "Open the NordLynx VPN config generator"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("nordConfig", forKey: "activeAppMode")
        return .result()
    }
}

nonisolated struct SitchomaticAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckStatsIntent(),
            phrases: [
                "Check stats in \(.applicationName)",
                "Show \(.applicationName) statistics"
            ],
            shortTitle: "Check Stats",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: OpenPPSRModeIntent(),
            phrases: [
                "Open PPSR in \(.applicationName)",
                "Start PPSR mode in \(.applicationName)"
            ],
            shortTitle: "Open PPSR",
            systemImageName: "bolt.shield.fill"
        )
        AppShortcut(
            intent: OpenLoginTestingIntent(),
            phrases: [
                "Open Login Testing in \(.applicationName)",
                "Start login test in \(.applicationName)"
            ],
            shortTitle: "Login Testing",
            systemImageName: "rectangle.split.2x1.fill"
        )
        AppShortcut(
            intent: OpenNordConfigIntent(),
            phrases: [
                "Open NordLynx in \(.applicationName)"
            ],
            shortTitle: "NordLynx Config",
            systemImageName: "network"
        )
    }
}
