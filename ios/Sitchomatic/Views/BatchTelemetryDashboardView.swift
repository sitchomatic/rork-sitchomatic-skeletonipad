import SwiftUI
import Charts

struct BatchTelemetryDashboardView: View {
    private let telemetry = BatchTelemetryService.shared
    @State private var selectedRecord: BatchTelemetryService.BatchRecord?
    @State private var showFilters: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if telemetry.batchRecords.isEmpty {
                    emptyState
                } else {
                    summaryCards
                    successRateChart
                    throughputChart
                    batchHistoryList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Batch Telemetry")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { showFilters.toggle() }
                } label: {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            BatchRecordDetailSheet(record: record)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Batch History")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            Text("Batch telemetry data will appear here after running batches.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(60)
        .frame(maxWidth: .infinity)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Total Batches",
                value: "\(telemetry.batchRecords.count)",
                icon: "square.stack.3d.up.fill",
                color: .blue
            )

            statCard(
                title: "Avg Success Rate",
                value: String(format: "%.1f%%", averageSuccessRate * 100),
                icon: "checkmark.circle.fill",
                color: .green
            )

            statCard(
                title: "Total Processed",
                value: "\(totalProcessedItems)",
                icon: "arrow.triangle.2.circlepath",
                color: .purple
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var successRateChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Success Rate Trend", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundStyle(.primary)

            if #available(iOS 16.0, *) {
                Chart(telemetry.batchRecords.suffix(20)) { record in
                    LineMark(
                        x: .value("Batch", record.batchId.prefix(8)),
                        y: .value("Success Rate", record.successRate * 100)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Batch", record.batchId.prefix(8)),
                        y: .value("Success Rate", record.successRate * 100)
                    )
                    .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var throughputChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Throughput per Minute", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)
                .foregroundStyle(.primary)

            if #available(iOS 16.0, *) {
                Chart(telemetry.batchRecords.suffix(20)) { record in
                    BarMark(
                        x: .value("Batch", record.batchId.prefix(8)),
                        y: .value("Throughput", record.throughputPerMinute)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var batchHistoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Batches", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(telemetry.batchRecords.reversed()) { record in
                Button {
                    selectedRecord = record
                } label: {
                    BatchRecordRow(record: record)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var averageSuccessRate: Double {
        guard !telemetry.batchRecords.isEmpty else { return 0 }
        let total = telemetry.batchRecords.reduce(0.0) { $0 + $1.successRate }
        return total / Double(telemetry.batchRecords.count)
    }

    private var totalProcessedItems: Int {
        telemetry.batchRecords.reduce(0) { $0 + $1.processedItems }
    }
}

struct BatchRecordRow: View {
    let record: BatchTelemetryService.BatchRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.batchId.prefix(12))
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundStyle(.primary)

                Text(record.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(String(format: "%.1f%%", record.successRate * 100))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text("\(record.processedItems)/\(record.totalItems)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct BatchRecordDetailSheet: View {
    let record: BatchTelemetryService.BatchRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Batch ID") {
                        Text(record.batchId)
                            .font(.system(.caption, design: .monospaced))
                    }
                    LabeledContent("Started", value: record.startedAt, format: .dateTime)
                    if let completed = record.completedAt {
                        LabeledContent("Completed", value: completed, format: .dateTime)
                    }
                    LabeledContent("Duration", value: "\(record.durationSeconds)s")
                }

                Section("Results") {
                    LabeledContent("Total Items", value: "\(record.totalItems)")
                    LabeledContent("Processed", value: "\(record.processedItems)")
                    LabeledContent("Success", value: "\(record.successCount)")
                    LabeledContent("Failures", value: "\(record.failureCount)")
                    LabeledContent("Success Rate", value: String(format: "%.2f%%", record.successRate * 100))
                }

                Section("Performance") {
                    LabeledContent("Throughput", value: String(format: "%.1f items/min", record.throughputPerMinute))
                    LabeledContent("Avg Latency", value: "\(record.avgLatencyMs)ms")
                }

                Section("Network") {
                    LabeledContent("Proxy Target", value: record.proxyTarget)
                    LabeledContent("Network Mode", value: record.networkMode)
                    LabeledContent("IP Rotations", value: "\(record.ipRotations)")
                }

                Section("Issues") {
                    LabeledContent("Connection Failures", value: "\(record.connectionFailures)")
                    LabeledContent("Timeouts", value: "\(record.timeouts)")
                    LabeledContent("Rate Limit Hits", value: "\(record.rateLimitHits)")
                    LabeledContent("Auto-Pause Triggers", value: "\(record.autoPauseTriggers)")
                }
            }
            .navigationTitle("Batch Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
