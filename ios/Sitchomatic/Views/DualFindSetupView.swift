import SwiftUI

struct DualFindSetupView: View {
    @Bindable var vm: DualFindViewModel
    let onStart: () -> Void
    let onResume: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.hasResumePoint {
                    resumeBanner
                }

                sessionPicker

                screenshotPicker

                settingsButton

                emailSection

                passwordSection

                if vm.parsedPasswordCount > 0 {
                    passwordQueuePreview
                }

                autoAdvanceToggle

                startButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dual Find")
        .navigationBarTitleDisplayMode(.large)
    }

    private var resumeBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Previous Run Available")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    if !vm.passwordSets.isEmpty {
                        let done = vm.passwordSets.filter { $0.status == .done }.count
                        Text("Set \(vm.currentSetIndex + 1) of \(vm.passwordSets.count) · \(done) completed")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text("Resume from where you left off")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                Button {
                    onResume()
                } label: {
                    Text("Resume")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.purple)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Button(role: .destructive) {
                    vm.clearResumePoint()
                } label: {
                    Text("Discard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }

                Spacer()
            }
        }
        .padding(14)
        .background(.purple.opacity(0.12))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var sessionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Session Count", systemImage: "rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Sessions", selection: $vm.sessionCount) {
                ForEach(DualFindSessionCount.allCases, id: \.rawValue) { count in
                    Text(count.label).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Email List", systemImage: "envelope.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if vm.parsedEmailCount > 0 {
                    Text("\(vm.parsedEmailCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.purple)
                        .clipShape(Capsule())
                }
            }

            TextEditor(text: $vm.emailInputText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if vm.emailInputText.isEmpty {
                        Text("Paste emails here, one per line...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Passwords", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if vm.parsedPasswordCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(vm.parsedPasswordCount)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))

                        Text("\(vm.parsedPasswordSetCount) set\(vm.parsedPasswordSetCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.purple)
                    .clipShape(Capsule())
                }
            }

            TextEditor(text: $vm.passwordInputText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if vm.passwordInputText.isEmpty {
                        Text("Paste passwords here, one per line...\nGrouped in sets of 3 automatically")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var passwordQueuePreview: some View {
        let previewSets = vm.buildPasswordSets(from: vm.parsePasswords(from: vm.passwordInputText))

        return VStack(alignment: .leading, spacing: 8) {
            Label("Password Queue", systemImage: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(previewSets) { set in
                queueSetCard(set: set, isPreview: true)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func queueSetCard(set: DualFindPasswordSet, isPreview: Bool) -> some View {
        let statusColor: Color = switch set.status {
        case .done: .green
        case .active: .cyan
        case .queued: .gray
        }

        let statusIcon: String = switch set.status {
        case .done: "checkmark.circle.fill"
        case .active: "play.circle.fill"
        case .queued: "clock"
        }

        let statusLabel: String = switch set.status {
        case .done: "Done"
        case .active: "Active"
        case .queued: "Queued"
        }

        return HStack(spacing: 10) {
            Text("\(set.index + 1)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.purple)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Set \(set.index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)

                Text(set.maskedPasswords.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isPreview {
                Text("\(set.count) pw")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10))
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(
            set.status == .active && !isPreview
                ? Color.cyan.opacity(0.06)
                : Color(.tertiarySystemGroupedBackground)
        )
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(set.status == .active && !isPreview ? .cyan.opacity(0.3) : .clear, lineWidth: 1)
        )
    }

    private var autoAdvanceToggle: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.purple.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Advance Sets")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Automatically start the next password set")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $vm.autoAdvanceEnabled)
                .labelsHidden()
                .tint(.purple)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var screenshotPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Screenshots Per Attempt", systemImage: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(vm.screenshotCount == .zero ? "Off" : "\(vm.screenshotCount.rawValue)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
            }

            Picker("Screenshots", selection: $vm.screenshotCount) {
                ForEach(DualFindScreenshotCount.allCases, id: \.rawValue) { count in
                    Text(count.label).tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var settingsButton: some View {
        Button {
            onSettings()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.purple.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Automation Settings")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Dual Find personalized configuration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var startButton: some View {
        Button {
            onStart()
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                    Text("Start Dual Find")
                        .font(.system(size: 16, weight: .bold))
                }

                if vm.parsedPasswordSetCount > 1 {
                    Text("\(vm.parsedPasswordSetCount) password sets queued")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(vm.canStart ? .purple : .gray.opacity(0.4))
            .clipShape(.rect(cornerRadius: 14))
        }
        .disabled(!vm.canStart)
        .sensoryFeedback(.impact(weight: .heavy), trigger: vm.isRunning)
        .padding(.bottom, 20)
    }
}
