import Foundation
import Synchronization

/// Lock-free, single-use continuation guard using Swift 6.2 `Mutex<Bool>`.
/// Guarantees exactly-once consumption without `@unchecked Sendable`.
nonisolated final class ContinuationGuard: Sendable {
    private let state = Mutex(false)

    func tryConsume() -> Bool {
        state.withLock { consumed in
            if consumed { return false }
            consumed = true
            return true
        }
    }
}
