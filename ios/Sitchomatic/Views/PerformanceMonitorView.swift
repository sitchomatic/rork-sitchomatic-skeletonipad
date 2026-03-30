import SwiftUI

struct PerformanceMonitorView: View {
    private let instrumentation = PerformanceInstrumentation.shared
    @State private var refreshTrigger: Int = 0
    @State private var selectedSubsystem: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                headerCard
                memoryTrackingSection
                signpostSection
                taskTrackingSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Performance Monitor")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshTrigger += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .id(refreshTrigger)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance Instrumentation")
                        .font(.headline)
                    Text("System-wide performance tracking with os_signpost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack {
                metricBadge(title: "Signpost", value: "Active", color: .green)
                metricBadge(title: "Memory", value: "Tracked", color: .blue)
                metricBadge(title: "Tasks", value: "Named", color: .purple)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func metricBadge(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var memoryTrackingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Subsystem Memory Tracking", systemImage: "memorychip")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Memory allocation tracking per subsystem with real-time monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                subsystemRow(name: "WebView Pool", usage: "Active", icon: "globe", color: .blue)
                subsystemRow(name: "Session Engine", usage: "Active", icon: "gearshape.2", color: .green)
                subsystemRow(name: "Automation", usage: "Active", icon: "bolt", color: .orange)
                subsystemRow(name: "Network Layer", usage: "Active", icon: "network", color: .purple)
                subsystemRow(name: "Screenshot Cache", usage: "Active", icon: "photo.stack", color: .pink)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func subsystemRow(name: String, usage: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Text(usage)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var signpostSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("OS Signpost Logging", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Structured performance logging with os_signpost for Instruments integration.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                signpostFeature(
                    title: "Interval Tracking",
                    description: "Begin/end signpost intervals for async operations",
                    icon: "timer",
                    color: .blue
                )

                signpostFeature(
                    title: "Event Markers",
                    description: "Point-in-time event markers for key moments",
                    icon: "mappin.and.ellipse",
                    color: .green
                )

                signpostFeature(
                    title: "Instruments Integration",
                    description: "View signposts in Xcode Instruments for deep analysis",
                    icon: "waveform.path.ecg",
                    color: .purple
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func signpostFeature(title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var taskTrackingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Named Task Tracking", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Swift 6.2 named tasks with automatic performance instrumentation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                taskFeature(
                    title: "Named Tasks",
                    description: "Structured concurrency with named task wrappers",
                    example: "namedTask(\"LoginFlow\")",
                    color: .blue
                )

                taskFeature(
                    title: "Detached Tasks",
                    description: "Long-running background tasks with isolation",
                    example: "namedDetachedTask(\"Sync\")",
                    color: .green
                )

                taskFeature(
                    title: "WebView Cleanup",
                    description: "Async defer for automatic resource cleanup",
                    example: "withWebViewCleanup()",
                    color: .orange
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func taskFeature(title: String, description: String, example: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "function")
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(example)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .clipShape(.rect(cornerRadius: 6))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct PerformanceMonitorInstrumentsGuide: View {
    var body: some View {
        List {
            Section {
                Text("1. Open Xcode and select Product > Profile (⌘I)")
                Text("2. Choose the 'os_signpost' instrument")
                Text("3. Start recording and use the app")
                Text("4. View signpost intervals and events")
            } header: {
                Label("Using with Instruments", systemImage: "doc.text")
            }

            Section {
                Text("• All async operations are automatically instrumented")
                Text("• Task names appear in the signpost timeline")
                Text("• Memory allocations are tracked per subsystem")
                Text("• WebView lifecycle events are logged")
            } header: {
                Label("What's Tracked", systemImage: "checkmark.circle")
            }

            Section {
                Text("Performance data is logged to the Xcode console and Instruments. Use Instruments for deep performance analysis, memory profiling, and bottleneck identification.")
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .navigationTitle("Instruments Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
