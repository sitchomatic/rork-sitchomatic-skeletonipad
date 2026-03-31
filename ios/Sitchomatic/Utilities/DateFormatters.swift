import Foundation

/// Pre-configured date formatters for consistent date/time formatting throughout the app.
/// All formatters are created once as `static let` and are immutable after initialization.
/// Thread-safe: `DateFormatter` instances are safe to use from any thread when not mutated.
nonisolated enum DateFormatters: Sendable {
    static nonisolated(unsafe) let timeWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static nonisolated(unsafe) let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static nonisolated(unsafe) let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static nonisolated(unsafe) let fullTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static nonisolated(unsafe) let exportTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static nonisolated(unsafe) let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f
    }()
}
