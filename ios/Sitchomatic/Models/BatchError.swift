import Foundation

/// Swift 6.2 typed error for batch operations
enum BatchError: Error, Sendable, CustomStringConvertible {
    case batchAlreadyRunning
    case batchNotRunning
    case invalidState(String)
    case operationTimeout
    case emergencyStopRequired
    case resourceExhaustion

    var description: String {
        switch self {
        case .batchAlreadyRunning:
            return "Batch is already running"
        case .batchNotRunning:
            return "No active batch"
        case .invalidState(let details):
            return "Invalid state: \(details)"
        case .operationTimeout:
            return "Operation timed out"
        case .emergencyStopRequired:
            return "Emergency stop required"
        case .resourceExhaustion:
            return "System resources exhausted"
        }
    }
}
