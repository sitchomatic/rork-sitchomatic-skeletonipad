import SwiftUI

struct DualFindLiveFeedView: View {
    @Bindable var vm: DualFindViewModel
    @State private var selectedScreenshot: DualFindLiveScreenshot?
    @State private var platformFilter: String = "All"
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [DualFindLiveScreenshot] {
        var result = vm.liveScreenshots
        if platformFilter != "All" {
            result = result.filter { $0.platform == platformFilter }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.email.localizedStandardContains(searchText) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                statsBar

                if vm.liveScreenshots.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noMatchState
                } else {
                    screenshotList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Live Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !vm.liveScreenshots.isEmpty {
                        Button(role: .destructive) {
                            vm.clearLiveScreenshots()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Filter by email")
            .sheet(item: $selectedScreenshot) { screenshot in
                DualFindScreenshotDetailSheet(screenshot: screenshot)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["All", "JoePoint", "Ignition Lite"], id: \.self) { option in
                    let isSelected = platformFilter == option
                    let count: Int = {
                        if option == "All" { return vm.liveScreenshots.count }
                        return vm.liveScreenshots.filter { $0.platform == option }.count
                    }()

                    Button {
                        withAnimation(.spring(duration: 0.25)) { platformFilter = option }
                    } label: {
                        HStack(spacing: 4) {
                            if option != "All" {
                                Image(systemName: option == "JoePoint" ? "suit.spade.fill" : "flame.fill")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(option == "JoePoint" ? "JOE" : option == "Ignition Lite" ? "IGN" : "All")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(isSelected ? .white.opacity(0.2) : .primary.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(isSelected ? platformColor(option).opacity(0.75) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: platformFilter)
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            statPill(value: "\(vm.liveScreenshots.count)", label: "Total", color: .cyan)
            statPill(value: "\(vm.screenshotCount.rawValue)", label: "Per Attempt", color: .purple)
            statPill(value: "\(uniqueEmails)", label: "Emails", color: .blue)

            Spacer()

            if vm.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var uniqueEmails: Int {
        Set(vm.liveScreenshots.map(\.email)).count
    }

    private var screenshotList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { screenshot in
                    Button { selectedScreenshot = screenshot } label: {
                        DualFindScreenshotTile(screenshot: screenshot)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
                .symbolEffect(.pulse.byLayer, options: .repeating)
            Text("No Screenshots Yet")
                .font(.title3.bold())
            Text("Screenshots are captured during each\nlogin attempt based on your setting.\nSet to \(vm.screenshotCount.label) per attempt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No Matching Screenshots")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func platformColor(_ platform: String) -> Color {
        switch platform {
        case "JoePoint": .green
        case "Ignition Lite": .orange
        default: .cyan
        }
    }
}

struct DualFindScreenshotTile: View {
    let screenshot: DualFindLiveScreenshot
    private let isJoe: Bool

    init(screenshot: DualFindLiveScreenshot) {
        self.screenshot = screenshot
        self.isJoe = screenshot.platform.contains("Joe")
    }

    var body: some View {
        VStack(spacing: 0) {
            Color(.secondarySystemBackground)
                .frame(height: 180)
                .overlay {
                    Image(uiImage: screenshot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadii: .init(topLeading: 12, topTrailing: 12)))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: isJoe ? "suit.spade.fill" : "flame.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isJoe ? .green : .orange)
                        Text(isJoe ? "JOE" : "IGN")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    Text(screenshot.step.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(stepColor.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(8)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(screenshot.formattedTime)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(screenshot.email)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(screenshot.password)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let host = URL(string: screenshot.url)?.host {
                    Text(host)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var stepColor: Color {
        switch screenshot.step {
        case "pre_submit": .blue
        case "post_submit": .purple
        case _ where screenshot.step.contains("success"): .green
        case _ where screenshot.step.contains("disabled"): .red
        case _ where screenshot.step.contains("noAccount"): .secondary
        default: .gray
        }
    }
}

struct DualFindScreenshotDetailSheet: View {
    let screenshot: DualFindLiveScreenshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: screenshot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 10) {
                        let isJoe = screenshot.platform.contains("Joe")
                        HStack {
                            Image(systemName: isJoe ? "suit.spade.fill" : "flame.fill")
                                .foregroundStyle(isJoe ? .green : .orange)
                            Text(screenshot.platform)
                                .font(.headline)
                            Spacer()
                            Text(screenshot.step.uppercased().replacingOccurrences(of: "_", with: " "))
                                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.purple)
                                .clipShape(Capsule())
                        }

                        VStack(spacing: 6) {
                            detailRow(icon: "person.fill", label: "Email", value: screenshot.email)
                            detailRow(icon: "key.fill", label: "Password", value: screenshot.password)
                            detailRow(icon: "link", label: "URL", value: URL(string: screenshot.url)?.host ?? screenshot.url)
                            detailRow(icon: "clock", label: "Time", value: screenshot.formattedTime)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))

                    Button {
                        UIPasteboard.general.string = "\(screenshot.email):\(screenshot.password)"
                    } label: {
                        Label("Copy Credentials", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.purple.opacity(0.8))
                            .clipShape(.rect(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Screenshot Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}
