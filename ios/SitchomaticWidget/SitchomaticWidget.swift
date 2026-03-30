import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

nonisolated struct BatchProgressEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let isPaused: Bool
    let successCount: Int
    let failCount: Int
    let totalCount: Int
    let pairCount: Int
    let throughputPerMinute: Double
    let eta: String

    static var placeholder: BatchProgressEntry {
        BatchProgressEntry(
            date: .now, isRunning: true, isPaused: false,
            successCount: 42, failCount: 3, totalCount: 100,
            pairCount: 45, throughputPerMinute: 12.5, eta: "4:30"
        )
    }

    static var idle: BatchProgressEntry {
        BatchProgressEntry(
            date: .now, isRunning: false, isPaused: false,
            successCount: 0, failCount: 0, totalCount: 0,
            pairCount: 0, throughputPerMinute: 0, eta: "--"
        )
    }

    var completedCount: Int { successCount + failCount }
    var progress: Double { totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0 }
}

// MARK: - Provider

nonisolated struct BatchProgressProvider: TimelineProvider {
    private let defaults = UserDefaults(suiteName: "group.com.sitchomatic.shared")

    func placeholder(in context: Context) -> BatchProgressEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (BatchProgressEntry) -> Void) {
        completion(context.isPreview ? .placeholder : readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatchProgressEntry>) -> Void) {
        let entry = readEntry()
        let refreshDate = Calendar.current.date(byAdding: .second, value: entry.isRunning ? 15 : 60, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func readEntry() -> BatchProgressEntry {
        guard let d = defaults else { return .idle }
        return BatchProgressEntry(
            date: .now,
            isRunning: d.bool(forKey: "widget_isRunning"),
            isPaused: d.bool(forKey: "widget_isPaused"),
            successCount: d.integer(forKey: "widget_successCount"),
            failCount: d.integer(forKey: "widget_failureCount"),
            totalCount: d.integer(forKey: "widget_totalCount"),
            pairCount: d.integer(forKey: "widget_pairCount"),
            throughputPerMinute: d.double(forKey: "widget_throughputPerMinute"),
            eta: d.string(forKey: "widget_eta") ?? "--"
        )
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: BatchProgressEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.isRunning ? (entry.isPaused ? "pause.circle.fill" : "bolt.circle.fill") : "moon.circle.fill")
                    .foregroundStyle(entry.isRunning ? (entry.isPaused ? .orange : .green) : .gray)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text(entry.isRunning ? (entry.isPaused ? "PAUSED" : "RUNNING") : "IDLE")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(entry.isRunning ? (entry.isPaused ? .orange : .green) : .gray)
            }
            Spacer()
            Text("\(entry.successCount)")
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundStyle(.green)
            Text("SUCCESS")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            if entry.failCount > 0 {
                Text("\(entry.failCount) fail")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumWidgetView: View {
    let entry: BatchProgressEntry
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: entry.isRunning ? "bolt.circle.fill" : "moon.circle.fill")
                    .foregroundStyle(entry.isRunning ? (entry.isPaused ? .orange : .green) : .gray)
                Text(entry.isRunning ? (entry.isPaused ? "PAUSED" : "RUNNING") : "IDLE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(entry.isRunning ? (entry.isPaused ? .orange : .green) : .gray)
                Spacer()
                if entry.isRunning {
                    Text("ETA \(entry.eta)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            ProgressView(value: entry.progress)
                .tint(entry.isPaused ? .orange : .green)
            HStack {
                metricView(value: "\(entry.successCount)", label: "OK", color: .green)
                Spacer()
                metricView(value: "\(entry.failCount)", label: "FAIL", color: .red)
                Spacer()
                metricView(value: "\(entry.pairCount)", label: "PAIRS", color: .cyan)
                Spacer()
                metricView(value: String(format: "%.1f", entry.throughputPerMinute), label: "/MIN", color: .white.opacity(0.7))
            }
        }
    }

    private func metricView(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct LargeWidgetView: View {
    let entry: BatchProgressEntry
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("COMMAND CENTER")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text(entry.isRunning ? (entry.isPaused ? "PAUSED" : "ACTIVE") : "IDLE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((entry.isRunning ? (entry.isPaused ? Color.orange : .green) : .gray).opacity(0.2))
                    .foregroundStyle(entry.isRunning ? (entry.isPaused ? .orange : .green) : .gray)
                    .clipShape(Capsule())
            }
            ProgressView(value: entry.progress)
                .tint(entry.isPaused ? .orange : .green)
            Text("\(entry.completedCount) / \(entry.totalCount)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Divider().background(.white.opacity(0.1))
            dashRow(icon: "checkmark.circle.fill", label: "Success", value: "\(entry.successCount)", color: .green)
            dashRow(icon: "xmark.circle.fill", label: "Failed", value: "\(entry.failCount)", color: .red)
            dashRow(icon: "person.2.fill", label: "Pairs", value: "\(entry.pairCount)", color: .cyan)
            dashRow(icon: "gauge.high", label: "Throughput", value: String(format: "%.1f/min", entry.throughputPerMinute), color: .white.opacity(0.8))
            dashRow(icon: "clock.fill", label: "ETA", value: entry.eta, color: .orange)
            Spacer(minLength: 0)
        }
    }

    private func dashRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 20)
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(color)
        }
    }
}

// MARK: - Widget

struct SitchomaticWidget: Widget {
    let kind: String = "SitchomaticWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatchProgressProvider()) { entry in
            Group {
                switch WidgetFamily.current(entry) {
                case .systemSmall: SmallWidgetView(entry: entry)
                case .systemMedium: MediumWidgetView(entry: entry)
                default: LargeWidgetView(entry: entry)
                }
            }
            .containerBackground(.black.opacity(0.92), for: .widget)
        }
        .configurationDisplayName("Sitchomatic APEX Widget")
        .description("Batch progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Family Helper

private extension WidgetFamily {
    static func current(_ entry: BatchProgressEntry) -> WidgetFamily {
        // Determined at render time by container; default to large
        .systemLarge
    }
}

