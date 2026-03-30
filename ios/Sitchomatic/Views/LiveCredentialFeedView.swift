import SwiftUI

struct LiveCredentialFeedView: View {
    @State private var screenshotManager = UnifiedScreenshotManager.shared
    @State private var selectedCredential: String?
    @State private var autoRefresh: Bool = true
    @State private var fullScreenImage: UnifiedScreenshot?

    private let maxEmailDisplayLength = 20

    private var credentialEmails: [String] {
        Array(Set(screenshotManager.screenshots.map(\.credentialEmail)))
            .sorted()
    }

    private var filteredScreenshots: [UnifiedScreenshot] {
        guard let email = selectedCredential else {
            return screenshotManager.screenshots
        }
        return screenshotManager.screenshots.filter { $0.credentialEmail == email }
    }

    private var latestScreenshot: UnifiedScreenshot? {
        filteredScreenshots.first
    }

    var body: some View {
        VStack(spacing: 0) {
            credentialPicker
            if filteredScreenshots.isEmpty {
                emptyState
            } else {
                livePreview
                screenshotTimeline
            }
        }
        .navigationTitle("Live Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    autoRefresh.toggle()
                } label: {
                    Image(systemName: autoRefresh ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(autoRefresh ? .green : .secondary)
                }
            }
        }
        .sheet(item: $fullScreenImage) { screenshot in
            NavigationStack {
                fullScreenViewer(screenshot)
            }
        }
    }

    // MARK: - Credential Picker

    private var credentialPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", isSelected: selectedCredential == nil) {
                    selectedCredential = nil
                }
                ForEach(credentialEmails, id: \.self) { email in
                    let count = screenshotManager.screenshots.filter { $0.credentialEmail == email }.count
                    chipButton(label: "\(email.prefix(maxEmailDisplayLength))… (\(count))", isSelected: selectedCredential == email) {
                        selectedCredential = email
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? .green : .secondary)
                .clipShape(Capsule())
        }
    }

    // MARK: - Live Preview

    private var livePreview: some View {
        VStack(spacing: 6) {
            if let latest = latestScreenshot {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: latest.displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { fullScreenImage = latest }

                    if autoRefresh {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                }

                HStack(spacing: 12) {
                    Label(latest.step.displayName, systemImage: latest.step.icon)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    Text(latest.outcomeLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(latest.outcomeColor.opacity(0.2))
                        .foregroundStyle(latest.outcomeColor)
                        .clipShape(Capsule())

                    Spacer()

                    Text(latest.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if !latest.credentialEmail.isEmpty {
                    Text(latest.credentialEmail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Screenshot Timeline

    private var screenshotTimeline: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(filteredScreenshots) { screenshot in
                    screenshotTile(screenshot)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func screenshotTile(_ screenshot: UnifiedScreenshot) -> some View {
        VStack(spacing: 4) {
            Image(uiImage: screenshot.displayImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(screenshot.outcomeColor.opacity(0.5), lineWidth: 1)
                )
                .onTapGesture { fullScreenImage = screenshot }

            Text(screenshot.step.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(screenshot.formattedTime)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Screenshots Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Screenshots will appear here in real time as login tests run.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Full Screen Viewer

    private func fullScreenViewer(_ screenshot: UnifiedScreenshot) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: screenshot.fullImage)
                .resizable()
                .aspectRatio(contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(screenshot.step.displayName, systemImage: screenshot.step.icon)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(screenshot.outcomeLabel)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(screenshot.outcomeColor.opacity(0.2))
                        .foregroundStyle(screenshot.outcomeColor)
                        .clipShape(Capsule())
                }

                Text(screenshot.credentialEmail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                if !screenshot.allDetectedText.isEmpty {
                    Text(screenshot.allDetectedText.prefix(200))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(4)
                }
            }
            .padding()
        }
        .navigationTitle("Screenshot Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { fullScreenImage = nil }
            }
        }
    }
}
