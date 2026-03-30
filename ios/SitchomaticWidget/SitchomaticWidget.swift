import WidgetKit
import SwiftUI

// MARK: - Batch Progress Entry

nonisolated struct BatchProgressEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let status: String
    let successCount: Int
    let totalCount: Int
    let pairCount: Int
    let throughputPerMin: Int
    let eta: String

    static let placeholder = BatchProgressEntry(
        date: .now,
        isRunning: false,
        status: "Idle",
        successCount: 0,
        totalCount: 0,
        pairCount: 0,
        throughputPerMin: 0,
        eta: "--:--"
    )
}

// MARK: - Provider

nonisolated struct BatchProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatchProgressEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BatchProgressEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatchProgressEntry>) -> Void) {
        // In a real implementation, this would read from shared UserDefaults or App Group
        let entry = BatchProgressEntry(
            date: .now,
            isRunning: false,
            status: "Ready",
            successCount: 0,
            totalCount: 0,
            pairCount: 0,
            throughputPerMin: 0,
            eta: "--:--"
        )

        let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60)))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct BatchProgressWidgetView: View {
    var entry: BatchProgressEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: entry.isRunning ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(entry.isRunning ? .green : .gray)
                Text(entry.status)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text("\(entry.successCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Completed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.isRunning ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(entry.status)
                        .font(.caption.bold())
                }

                Text("\(entry.successCount)/\(entry.totalCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Text("\(entry.pairCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("pairs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("\(entry.throughputPerMin)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("/min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("ETA: \(entry.eta)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var largeView: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.isRunning ? .green : .gray)
                        .frame(width: 12, height: 12)
                    Text(entry.status)
                        .font(.headline)
                }
                Spacer()
                Text("Sitchomatic")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 24) {
                StatBox(title: "Completed", value: "\(entry.successCount)/\(entry.totalCount)")
                StatBox(title: "Active Pairs", value: "\(entry.pairCount)")
            }

            HStack(spacing: 24) {
                StatBox(title: "Throughput", value: "\(entry.throughputPerMin)/min")
                StatBox(title: "ETA", value: entry.eta)
            }

            if entry.isRunning {
                let progress = entry.totalCount > 0 ? Double(entry.successCount) / Double(entry.totalCount) : 0
                ProgressView(value: progress)
                    .tint(.green)
            }
        }
        .padding()
    }
}

struct StatBox: View {
    let title: String
    let value: String

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
            BatchProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sitchomatic Batch Progress")
        .description("Track your automation batch progress in real-time")
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

