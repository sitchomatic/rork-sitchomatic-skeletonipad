import Foundation

/// Keyed task collection with automatic cancellation on replacement and cleanup.
@MainActor
final class TaskBag {
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Add a task under `key`, cancelling any prior task with the same key.
    @discardableResult
    func add(_ key: String, _ task: Task<Void, Never>) -> Task<Void, Never> {
        tasks[key]?.cancel()
        tasks[key] = task
        return task
    }

    /// Cancel and remove the task for `key`.
    func cancel(_ key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    /// Cancel and remove all tracked tasks.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Whether a task exists for the given key.
    func contains(_ key: String) -> Bool {
        tasks[key] != nil
    }

    var activeKeys: [String] { Array(tasks.keys) }
    var count: Int { tasks.count }
    var isEmpty: Bool { tasks.isEmpty }

    deinit {
        for task in tasks.values { task.cancel() }
    }
}
