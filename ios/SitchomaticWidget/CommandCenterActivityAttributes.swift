import ActivityKit
import Foundation

nonisolated struct CommandCenterActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var completedCount: Int
        var totalCount: Int
        var workingCount: Int
        var failedCount: Int
        var statusLabel: String
        var elapsedSeconds: Int
        var isPaused: Bool
        var isStopping: Bool
        var successRate: Double
        var throughputPerMinute: Double
        var eta: String
        var pairCount: Int
    }

    var siteLabel: String
    var siteMode: String
    var batchLabel: String
}
