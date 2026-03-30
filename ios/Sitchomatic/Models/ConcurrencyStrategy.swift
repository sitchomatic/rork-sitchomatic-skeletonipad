import SwiftUI

nonisolated enum ConcurrencyStrategy: String, Codable, CaseIterable, Sendable, Identifiable {
    case rorkAISmart = "rorkAISmart"
    case fullSend = "fullSend"
    case liveUserAdjustable = "liveUserAdjustable"
    case fixedPairs = "fixedPairs"
    case conservativeSafe = "conservativeSafe"

    nonisolated var id: String { rawValue }

    var label: String {
        switch self {
        case .rorkAISmart: "RorkAI Smart"
        case .fullSend: "Start & Stay Max"
        case .liveUserAdjustable: "Live Adjustable"
        case .fixedPairs: "Fixed Pairs"
        case .conservativeSafe: "Heuristic Ramp"
        }
    }

    var icon: String {
        switch self {
        case .rorkAISmart: "brain.head.profile.fill"
        case .fullSend: "bolt.horizontal.fill"
        case .liveUserAdjustable: "slider.horizontal.3"
        case .fixedPairs: "lock.fill"
        case .conservativeSafe: "tortoise.fill"
        }
    }

    var description: String {
        switch self {
        case .rorkAISmart:
            "AI + heuristics merged. Starts at 1 pair, ramps up cautiously based on live metrics (memory, success rate, latency). Grok AI analyzes every ~30s for deeper adjustments. Set it and forget it."
        case .fullSend:
            "Launches immediately at max pairs and stays there. No ramp-up, no ramp-down. Only drops on memory death spiral to prevent crash, then returns to max once recovered."
        case .liveUserAdjustable:
            "You control pairs live with a slider during the run. Changes apply after the current wave of pairs completes — a pending badge shows until it takes effect."
        case .fixedPairs:
            "Pick your exact pair count before starting (1–10). Stays locked for the entire run. No AI, no heuristics, no adjustment. Simple and predictable."
        case .conservativeSafe:
            "Heuristic ramp up & down. Starts at 1 pair, requires 8 consecutive successes to ramp +1 pair (60s cooldown). Ramps down on any single failure. Max cap halved from your setting."
        }
    }

    var tintColor: Color {
        switch self {
        case .rorkAISmart: .cyan
        case .fullSend: .red
        case .liveUserAdjustable: .purple
        case .fixedPairs: .orange
        case .conservativeSafe: .green
        }
    }

    var usesAI: Bool {
        self == .rorkAISmart
    }

    var usesHeuristics: Bool {
        self == .rorkAISmart || self == .conservativeSafe
    }

    var allowsRampUp: Bool {
        self == .rorkAISmart || self == .conservativeSafe
    }

    var allowsRampDown: Bool {
        self == .rorkAISmart || self == .conservativeSafe
    }

    var startsAtMax: Bool {
        self == .fullSend
    }

    var isFixed: Bool {
        self == .fixedPairs || self == .fullSend
    }

    var isUserControlled: Bool {
        self == .liveUserAdjustable
    }
}
