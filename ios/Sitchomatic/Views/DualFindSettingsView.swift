import Foundation
import SwiftUI

struct DualFindSettingsView: View {
    @Bindable var vm: DualFindViewModel
    @State private var showSuccessMarkerEditor: Bool = false
    @State private var showTerminalKeywordEditor: Bool = false
    @State private var showErrorBannerEditor: Bool = false
    @State private var showButtonTextEditor: Bool = false
    @State private var showMFAKeywordEditor: Bool = false
    @State private var showCaptchaKeywordEditor: Bool = false
    @State private var showPatternReorder: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var lastSaveTime: Date? = nil
    @State private var autoSaveEnabled: Bool = true

    private let accentColor: Color = .purple

    private var settingsHash: String {
        (try? String(data: JSONEncoder().encode(vm.automationSettings), encoding: .utf8)) ?? ""
    }

    var body: some View {
        List {
            autoSaveSection
            systemConfigSection
            trueDetectionSection
            pageLoadingSection
            fieldDetectionSection
            credentialEntrySection
            submitBehaviorSection
            timeDelaysSection
            postSubmitEvalSection
            retryRequeueSection
            patternStrategySection
            stealthSection
            humanSimulationSection
            screenshotDebugSection
            concurrencySection
            sessionManagementSection
            mfaHandlingSection
            captchaHandlingSection
            blankPageRecoverySection
            networkPerModeSection
            errorClassificationSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dual Find Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: settingsHash) { _, _ in
            if autoSaveEnabled {
                vm.persistDualFindSettings()
                lastSaveTime = Date()
                withAnimation(.spring(duration: 0.3)) { showSavedToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation { showSavedToast = false }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Auto-saved")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.purple.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showSuccessMarkerEditor) {
            NavigationStack { KeywordListEditor(title: "Success Markers", keywords: $vm.automationSettings.trueDetectionSuccessMarkers) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showTerminalKeywordEditor) {
            NavigationStack { KeywordListEditor(title: "Terminal Keywords", keywords: $vm.automationSettings.trueDetectionTerminalKeywords) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showErrorBannerEditor) {
            NavigationStack { KeywordListEditor(title: "Error Banner Selectors", keywords: $vm.automationSettings.trueDetectionErrorBannerSelectors) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showButtonTextEditor) {
            NavigationStack { KeywordListEditor(title: "Button Text Matches", keywords: $vm.automationSettings.loginButtonTextMatches) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showMFAKeywordEditor) {
            NavigationStack { KeywordListEditor(title: "MFA Keywords", keywords: $vm.automationSettings.mfaKeywords) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showCaptchaKeywordEditor) {
            NavigationStack { KeywordListEditor(title: "CAPTCHA Keywords", keywords: $vm.automationSettings.captchaKeywords) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showPatternReorder) {
            NavigationStack { PatternPriorityView(settings: $vm.automationSettings) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    // MARK: - Auto-Save

    private var autoSaveSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: autoSaveEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                    .font(.title3)
                    .foregroundStyle(autoSaveEnabled ? accentColor : .secondary)
                    .symbolEffect(.pulse, isActive: autoSaveEnabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Save")
                        .font(.subheadline.weight(.bold))
                    if let lastSave = lastSaveTime {
                        Text("Last saved: \(lastSave, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Saves after every change")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $autoSaveEnabled)
                    .labelsHidden()
                    .tint(accentColor)
            }

            if !autoSaveEnabled {
                Button {
                    vm.persistDualFindSettings()
                    lastSaveTime = Date()
                    withAnimation(.spring(duration: 0.3)) { showSavedToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation { showSavedToast = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save Now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 10))
                }
                .sensoryFeedback(.success, trigger: lastSaveTime)
            }
        } header: {
            Label("Persistence", systemImage: "externaldrive.fill")
        }
    }

    // MARK: - System Config

    private var systemConfigSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.purple.opacity(0.3), .pink.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 40, height: 40)
                    HStack(spacing: 2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.purple)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.pink)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dual Find")
                        .font(.subheadline.bold())
                    Text("V5.2 — email × password dual-site scan")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("V5.2")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Toggle(isOn: $vm.stealthEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("Stealth Mode")
                        .font(.subheadline)
                }
            }
            .tint(.purple)
            .disabled(vm.isRunning)

            Toggle(isOn: $vm.debugMode) {
                HStack(spacing: 6) {
                    Image(systemName: "ant.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Debug Mode")
                        .font(.subheadline)
                }
            }
            .tint(.orange)
            .disabled(vm.isRunning)

            Button {
                let loginVM = LoginViewModel.shared
                vm.automationSettings = loginVM.automationSettings
                vm.persistDualFindSettings()
                vm.log("Imported automation settings from Login VM", level: .success)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Login Settings")
                            .font(.subheadline.bold())
                        Text("Copy all automation settings from Login VM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Button {
                let unifiedVM = UnifiedSessionViewModel.shared
                vm.automationSettings = unifiedVM.automationSettings
                vm.persistDualFindSettings()
                vm.log("Imported automation settings from Unified Sessions", level: .success)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Unified Sessions")
                            .font(.subheadline.bold())
                        Text("Copy all automation settings from Unified VM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Button {
                vm.automationSettings = AutomationSettings()
                vm.persistDualFindSettings()
                vm.log("Reset automation settings to defaults", level: .warning)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.orange)
                    Text("Reset to Defaults")
                        .font(.subheadline)
                    Spacer()
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2.fill")
                Text("System")
            }
        } footer: {
            Text("These settings are independent from Login VM and Unified Sessions. Changes here only affect Dual Find.")
        }
    }

    // MARK: - TRUE DETECTION

    private var trueDetectionSection: some View {
        Section {
            Toggle(isOn: $vm.automationSettings.trueDetectionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRUE DETECTION")
                        .font(.headline)
                    Text("Hardcoded interaction — bypasses DOM detection")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)

            if vm.automationSettings.trueDetectionEnabled {
                Toggle("Always First Priority", isOn: $vm.automationSettings.trueDetectionPriority)
                    .tint(accentColor)

                Group {
                    Stepper("Hard Pause: \(vm.automationSettings.trueDetectionHardPauseMs)ms", value: $vm.automationSettings.trueDetectionHardPauseMs, in: 1000...8000, step: 500)
                    Stepper("Click Count: \(vm.automationSettings.trueDetectionTripleClickCount)", value: $vm.automationSettings.trueDetectionTripleClickCount, in: 1...10)
                    Stepper("Click Delay: \(vm.automationSettings.trueDetectionTripleClickDelayMs)ms", value: $vm.automationSettings.trueDetectionTripleClickDelayMs, in: 200...3000, step: 100)
                    Stepper("Submit Cycles: \(vm.automationSettings.trueDetectionSubmitCycleCount)", value: $vm.automationSettings.trueDetectionSubmitCycleCount, in: 1...8)
                    Stepper("Button Recovery: \(vm.automationSettings.trueDetectionButtonRecoveryTimeoutMs)ms", value: $vm.automationSettings.trueDetectionButtonRecoveryTimeoutMs, in: 2000...30000, step: 1000)
                    Stepper("Max Attempts: \(vm.automationSettings.trueDetectionMaxAttempts)", value: $vm.automationSettings.trueDetectionMaxAttempts, in: 1...10)
                    Stepper("Post-Click Wait: \(vm.automationSettings.trueDetectionPostClickWaitMs)ms", value: $vm.automationSettings.trueDetectionPostClickWaitMs, in: 500...5000, step: 250)
                    Stepper("Cooldown: \(vm.automationSettings.trueDetectionCooldownMinutes) min", value: $vm.automationSettings.trueDetectionCooldownMinutes, in: 1...60)
                }

                dfSelectorField("Email Selector", placeholder: "#email", binding: $vm.automationSettings.trueDetectionEmailSelector)
                dfSelectorField("Password Selector", placeholder: "#login-password", binding: $vm.automationSettings.trueDetectionPasswordSelector)
                dfSelectorField("Submit Selector", placeholder: "#login-submit", binding: $vm.automationSettings.trueDetectionSubmitSelector)

                Button { showSuccessMarkerEditor = true } label: {
                    dfKeywordRow("Success Markers", count: vm.automationSettings.trueDetectionSuccessMarkers.count)
                }
                Button { showTerminalKeywordEditor = true } label: {
                    dfKeywordRow("Terminal Keywords", count: vm.automationSettings.trueDetectionTerminalKeywords.count)
                }
                Button { showErrorBannerEditor = true } label: {
                    dfKeywordRow("Error Banner Selectors", count: vm.automationSettings.trueDetectionErrorBannerSelectors.count)
                }

                Toggle("No Proxy Rotation", isOn: $vm.automationSettings.trueDetectionNoProxyRotation)
                    .tint(accentColor)
                Toggle("Strict Waits", isOn: $vm.automationSettings.trueDetectionStrictWaits)
                    .tint(accentColor)
                Toggle("Ignore Placeholders", isOn: $vm.automationSettings.trueDetectionIgnorePlaceholders)
                    .tint(accentColor)
                Toggle("Ignore XPaths", isOn: $vm.automationSettings.trueDetectionIgnoreXPaths)
                    .tint(accentColor)
                Toggle("Ignore Class Names", isOn: $vm.automationSettings.trueDetectionIgnoreClassNames)
                    .tint(accentColor)
                Toggle("Always Force Enabled", isOn: $vm.automationSettings.trueDetectionAlwaysForceEnabled)
                    .tint(accentColor)
            }
        } header: {
            HStack {
                Image(systemName: "shield.checkered")
                Text("TRUE DETECTION Protocol")
            }
        } footer: {
            Text("V5.2: Triple-click escalating dwell primary. Settlement gate waits for button color reversion before evaluation.")
        }
    }

    // MARK: - Page Loading

    private var pageLoadingSection: some View {
        Section {
            HStack {
                Image(systemName: "globe").foregroundStyle(.blue)
                Text("Page Load Timeout")
                Spacer()
                Picker("", selection: Binding(
                    get: { Int(vm.automationSettings.pageLoadTimeout) },
                    set: { vm.automationSettings.pageLoadTimeout = TimeInterval($0) }
                )) {
                    Text("90s").tag(90)
                    Text("120s").tag(120)
                    Text("150s").tag(150)
                    Text("180s").tag(180)
                }
                .pickerStyle(.menu)
            }
            Stepper("Load Retries: \(vm.automationSettings.pageLoadRetries)", value: $vm.automationSettings.pageLoadRetries, in: 1...10)
            Stepper("JS Render Wait: \(vm.automationSettings.waitForJSRenderMs)ms", value: $vm.automationSettings.waitForJSRenderMs, in: 1000...15000, step: 500)
            Toggle(isOn: $vm.automationSettings.fullSessionResetOnFinalRetry) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Reset on Final Retry")
                    Text("Destroy and rebuild WKWebView on last attempt").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)
        } header: {
            Label("Page Loading", systemImage: "globe")
        }
    }

    // MARK: - Field Detection

    private var fieldDetectionSection: some View {
        Section {
            Toggle(isOn: $vm.automationSettings.fieldVerificationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Field Verification")
                    Text("Verify email/password fields exist before filling").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accentColor)
            Toggle("Auto-Calibration", isOn: $vm.automationSettings.autoCalibrationEnabled)
                .tint(accentColor)
            Toggle("Vision ML Fallback", isOn: $vm.automationSettings.visionMLCalibrationFallback)
                .tint(accentColor)
        } header: {
            Label("Field Detection", systemImage: "text.cursor")
        }
    }

    // MARK: - Credential Entry

    private var credentialEntrySection: some View {
        Section {
            Stepper("Typing Min: \(vm.automationSettings.typingSpeedMinMs)ms", value: $vm.automationSettings.typingSpeedMinMs, in: 20...500, step: 10)
            Stepper("Typing Max: \(vm.automationSettings.typingSpeedMaxMs)ms", value: $vm.automationSettings.typingSpeedMaxMs, in: 50...800, step: 10)
            Toggle("Typing Jitter", isOn: $vm.automationSettings.typingJitterEnabled)
                .tint(accentColor)
            Toggle("Occasional Backspace", isOn: $vm.automationSettings.occasionalBackspaceEnabled)
                .tint(accentColor)
            Stepper("Field Focus Delay: \(vm.automationSettings.fieldFocusDelayMs)ms", value: $vm.automationSettings.fieldFocusDelayMs, in: 50...2000, step: 50)
            Stepper("Inter-Field Delay: \(vm.automationSettings.interFieldDelayMs)ms", value: $vm.automationSettings.interFieldDelayMs, in: 100...3000, step: 50)
            Toggle("Dismiss Cookie Notices", isOn: $vm.automationSettings.dismissCookieNotices)
                .tint(accentColor)
        } header: {
            Label("Credential Entry", systemImage: "keyboard")
        }
    }

    // MARK: - Submit Behavior

    private var submitBehaviorSection: some View {
        Section {
            Stepper("Submit Retries: \(vm.automationSettings.submitRetryCount)", value: $vm.automationSettings.submitRetryCount, in: 1...10)
            Stepper("Retry Delay: \(vm.automationSettings.submitRetryDelayMs)ms", value: $vm.automationSettings.submitRetryDelayMs, in: 1000...15000, step: 500)
            HStack {
                Text("Wait for Response")
                Spacer()
                Picker("", selection: Binding(
                    get: { Int(vm.automationSettings.waitForResponseSeconds) },
                    set: { vm.automationSettings.waitForResponseSeconds = Double($0) }
                )) {
                    Text("60s").tag(60)
                    Text("90s").tag(90)
                    Text("120s").tag(120)
                    Text("180s").tag(180)
                }
                .pickerStyle(.menu)
            }
            Toggle("Rapid Poll", isOn: $vm.automationSettings.rapidPollEnabled)
                .tint(accentColor)
            Stepper("Max Submit Cycles: \(vm.automationSettings.maxSubmitCycles)", value: $vm.automationSettings.maxSubmitCycles, in: 1...10)

            Picker("Button Detection", selection: $vm.automationSettings.loginButtonDetectionMode) {
                ForEach(AutomationSettings.ButtonDetectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Picker("Click Method", selection: $vm.automationSettings.loginButtonClickMethod) {
                ForEach(AutomationSettings.ButtonClickMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }

            Button { showButtonTextEditor = true } label: {
                dfKeywordRow("Button Text Matches", count: vm.automationSettings.loginButtonTextMatches.count)
            }

        } header: {
            Label("Submit Behavior", systemImage: "arrow.right.circle.fill")
        }
    }

    // MARK: - Time Delays

    private var timeDelaysSection: some View {
        Section {
            Stepper("Pre-Navigation: \(vm.automationSettings.preNavigationDelayMs)ms", value: $vm.automationSettings.preNavigationDelayMs, in: 0...5000, step: 100)
            Stepper("Post-Navigation: \(vm.automationSettings.postNavigationDelayMs)ms", value: $vm.automationSettings.postNavigationDelayMs, in: 0...5000, step: 100)
            Stepper("Pre-Typing: \(vm.automationSettings.preTypingDelayMs)ms", value: $vm.automationSettings.preTypingDelayMs, in: 0...5000, step: 50)
            Stepper("Post-Typing: \(vm.automationSettings.postTypingDelayMs)ms", value: $vm.automationSettings.postTypingDelayMs, in: 0...5000, step: 50)
            Stepper("Pre-Submit: \(vm.automationSettings.preSubmitDelayMs)ms", value: $vm.automationSettings.preSubmitDelayMs, in: 0...5000, step: 50)
            Stepper("Post-Submit: \(vm.automationSettings.postSubmitDelayMs)ms", value: $vm.automationSettings.postSubmitDelayMs, in: 0...5000, step: 100)
            Stepper("Between Attempts: \(vm.automationSettings.betweenAttemptsDelayMs)ms", value: $vm.automationSettings.betweenAttemptsDelayMs, in: 0...10000, step: 250)
            Stepper("Page Stabilization: \(vm.automationSettings.pageStabilizationDelayMs)ms", value: $vm.automationSettings.pageStabilizationDelayMs, in: 0...5000, step: 100)
            Stepper("Page Load Extra: \(vm.automationSettings.pageLoadExtraDelayMs)ms", value: $vm.automationSettings.pageLoadExtraDelayMs, in: 0...10000, step: 500)
            Stepper("Submit Button Wait: \(vm.automationSettings.submitButtonWaitDelayMs)ms", value: $vm.automationSettings.submitButtonWaitDelayMs, in: 0...10000, step: 500)
            Toggle("Delay Randomization", isOn: $vm.automationSettings.delayRandomizationEnabled)
                .tint(accentColor)
            if vm.automationSettings.delayRandomizationEnabled {
                Stepper("Randomization: \u{00B1}\(vm.automationSettings.delayRandomizationPercent)%", value: $vm.automationSettings.delayRandomizationPercent, in: 5...50, step: 5)
            }
        } header: {
            Label("Time Delays", systemImage: "timer")
        }
    }

    // MARK: - Post-Submit Evaluation

    private var postSubmitEvalSection: some View {
        Section {
            Toggle("Redirect Detection", isOn: $vm.automationSettings.redirectDetection)
                .tint(accentColor)
            Toggle("Content Change Detection", isOn: $vm.automationSettings.contentChangeDetection)
                .tint(accentColor)
            Toggle("Error Banner Detection", isOn: $vm.automationSettings.errorBannerDetection)
                .tint(accentColor)
            Toggle("Capture Page Content", isOn: $vm.automationSettings.capturePageContent)
                .tint(accentColor)
            Picker("Evaluation Strictness", selection: $vm.automationSettings.evaluationStrictness) {
                ForEach(AutomationSettings.EvaluationStrictness.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
        } header: {
            Label("Post-Submit Evaluation", systemImage: "checkmark.shield.fill")
        } footer: {
            Text("V5.2 strict cascade: incorrect\u{2192}disabled\u{2192}temp lock\u{2192}SMS/2FA\u{2192}success\u{2192}unsure")
        }
    }

    // MARK: - Retry / Requeue

    private var retryRequeueSection: some View {
        Section {
            Toggle("Requeue on Timeout", isOn: $vm.automationSettings.requeueOnTimeout)
                .tint(accentColor)
            Toggle("Requeue on Connection Failure", isOn: $vm.automationSettings.requeueOnConnectionFailure)
                .tint(accentColor)
            Toggle("Requeue on Unsure", isOn: $vm.automationSettings.requeueOnUnsure)
                .tint(accentColor)
            Toggle("Requeue on Red Banner", isOn: $vm.automationSettings.requeueOnRedBanner)
                .tint(accentColor)
            Stepper("Max Requeue: \(vm.automationSettings.maxRequeueCount)", value: $vm.automationSettings.maxRequeueCount, in: 0...10)
            Stepper("Min Attempts Before No Acc: \(vm.automationSettings.minAttemptsBeforeNoAcc)", value: $vm.automationSettings.minAttemptsBeforeNoAcc, in: 1...10)
        } header: {
            Label("Retry / Requeue", systemImage: "arrow.counterclockwise")
        }
    }

    // MARK: - Pattern Strategy

    private var patternStrategySection: some View {
        Section {
            Toggle("Prefer Calibrated First", isOn: $vm.automationSettings.preferCalibratedPatternsFirst)
                .tint(accentColor)
            Toggle("Pattern Learning", isOn: $vm.automationSettings.patternLearningEnabled)
                .tint(accentColor)
            Toggle("AI Telemetry", isOn: $vm.automationSettings.aiTelemetryEnabled)
                .tint(accentColor)
            Button { showPatternReorder = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pattern Priority Order")
                        Text("\(vm.automationSettings.enabledPatterns.count) enabled").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }

            Toggle("Fallback to Legacy Fill", isOn: $vm.automationSettings.fallbackToLegacyFill)
                .tint(accentColor)
            Toggle("Fallback to OCR Click", isOn: $vm.automationSettings.fallbackToOCRClick)
                .tint(accentColor)
            Toggle("Fallback to VisionML Click", isOn: $vm.automationSettings.fallbackToVisionMLClick)
                .tint(accentColor)
            Toggle("Fallback to Coordinate Click", isOn: $vm.automationSettings.fallbackToCoordinateClick)
                .tint(accentColor)
        } header: {
            Label("Pattern Strategy", systemImage: "list.bullet.indent")
        }
    }

    // MARK: - Stealth

    private var stealthSection: some View {
        Section {
            Toggle("Stealth JS Injection", isOn: $vm.automationSettings.stealthJSInjection)
                .tint(accentColor)
            Toggle("Fingerprint Spoofing", isOn: $vm.automationSettings.fingerprintSpoofing)
                .tint(accentColor)
            Toggle("User Agent Rotation", isOn: $vm.automationSettings.userAgentRotation)
                .tint(accentColor)
            Toggle("Viewport Randomization", isOn: $vm.automationSettings.viewportRandomization)
                .tint(accentColor)
            Toggle("WebGL Noise", isOn: $vm.automationSettings.webGLNoise)
                .tint(accentColor)
            Toggle("Canvas Noise", isOn: $vm.automationSettings.canvasNoise)
                .tint(accentColor)
            Toggle("AudioContext Noise", isOn: $vm.automationSettings.audioContextNoise)
                .tint(accentColor)
            Toggle("Timezone Spoof", isOn: $vm.automationSettings.timezoneSpoof)
                .tint(accentColor)
            Toggle("Language Spoof", isOn: $vm.automationSettings.languageSpoof)
                .tint(accentColor)
        } header: {
            Label("Stealth", systemImage: "eye.slash.fill")
        }
    }

    // MARK: - Human Simulation

    private var humanSimulationSection: some View {
        Section {
            Toggle("Human Mouse Movement", isOn: $vm.automationSettings.humanMouseMovement)
                .tint(accentColor)
            Toggle("Scroll Jitter", isOn: $vm.automationSettings.humanScrollJitter)
                .tint(accentColor)
            Toggle("Random Pre-Action Pause", isOn: $vm.automationSettings.randomPreActionPause)
                .tint(accentColor)
            if vm.automationSettings.randomPreActionPause {
                Stepper("Min: \(vm.automationSettings.preActionPauseMinMs)ms", value: $vm.automationSettings.preActionPauseMinMs, in: 10...1000, step: 10)
                Stepper("Max: \(vm.automationSettings.preActionPauseMaxMs)ms", value: $vm.automationSettings.preActionPauseMaxMs, in: 50...2000, step: 10)
            }
            Toggle("Gaussian Timing", isOn: $vm.automationSettings.gaussianTimingDistribution)
                .tint(accentColor)
        } header: {
            Label("Human Simulation", systemImage: "hand.tap.fill")
        }
    }

    // MARK: - Screenshot / Debug

    private var screenshotDebugSection: some View {
        Section {
            Toggle("Slow Debug Mode", isOn: $vm.automationSettings.slowDebugMode)
                .tint(.orange)
            Toggle("Screenshot on Every Eval", isOn: $vm.automationSettings.screenshotOnEveryEval)
                .tint(accentColor)
            Toggle("Screenshot on Failure", isOn: $vm.automationSettings.screenshotOnFailure)
                .tint(accentColor)
            Toggle("Screenshot on Success", isOn: $vm.automationSettings.screenshotOnSuccess)
                .tint(accentColor)
            Picker("Screenshots Per Attempt", selection: $vm.automationSettings.screenshotsPerAttempt) {
                ForEach(AutomationSettings.ScreenshotsPerAttempt.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            Stepper("Max Retention: \(vm.automationSettings.maxScreenshotRetention)", value: $vm.automationSettings.maxScreenshotRetention, in: 50...2000, step: 50)
        } header: {
            Label("Screenshot / Debug", systemImage: "camera.viewfinder")
        }
    }

    // MARK: - Concurrency

    private var concurrencySection: some View {
        Section {
            Picker("Strategy", selection: $vm.automationSettings.concurrencyStrategy) {
                ForEach(ConcurrencyStrategy.allCases) { strategy in
                    Label(strategy.label, systemImage: strategy.icon).tag(strategy)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: vm.automationSettings.concurrencyStrategy.icon)
                        .font(.caption)
                        .foregroundStyle(vm.automationSettings.concurrencyStrategy.tintColor)
                    Text(vm.automationSettings.concurrencyStrategy.label)
                        .font(.caption.bold())
                        .foregroundStyle(vm.automationSettings.concurrencyStrategy.tintColor)
                }
                Text(vm.automationSettings.concurrencyStrategy.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Stepper("Max Pair Cap: \(vm.automationSettings.maxConcurrency)", value: $vm.automationSettings.maxConcurrency, in: 1...20)

            if vm.automationSettings.concurrencyStrategy == .fixedPairs {
                Stepper("Fixed Pairs: \(vm.automationSettings.fixedPairCount)", value: $vm.automationSettings.fixedPairCount, in: 1...20)
            }

            if vm.automationSettings.concurrencyStrategy == .liveUserAdjustable {
                Stepper("Starting Pairs: \(vm.automationSettings.liveUserPairCount)", value: $vm.automationSettings.liveUserPairCount, in: 1...20)
            }

            Stepper("Batch Delay: \(vm.automationSettings.batchDelayBetweenStartsMs)ms", value: $vm.automationSettings.batchDelayBetweenStartsMs, in: 0...10000, step: 500)
            Toggle("Connection Test Before Batch", isOn: $vm.automationSettings.connectionTestBeforeBatch)
                .tint(accentColor)
        } header: {
            Label("Concurrency Strategy", systemImage: "arrow.triangle.branch")
        }
    }

    // MARK: - Session Management

    private var sessionManagementSection: some View {
        Section {
            Picker("Session Isolation", selection: $vm.automationSettings.sessionIsolation) {
                ForEach(AutomationSettings.SessionIsolationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Toggle("Clear Cookies Between Attempts", isOn: $vm.automationSettings.clearCookiesBetweenAttempts)
                .tint(accentColor)
            Toggle("Clear LocalStorage", isOn: $vm.automationSettings.clearLocalStorageBetweenAttempts)
                .tint(accentColor)
            Toggle("Clear SessionStorage", isOn: $vm.automationSettings.clearSessionStorageBetweenAttempts)
                .tint(accentColor)
            Toggle("Fresh WebView Per Attempt", isOn: $vm.automationSettings.freshWebViewPerAttempt)
                .tint(accentColor)
            Picker("Field Clear Method", selection: $vm.automationSettings.clearFieldMethod) {
                ForEach(AutomationSettings.FieldClearMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            Toggle("Click Field Before Typing", isOn: $vm.automationSettings.clickFieldBeforeTyping)
                .tint(accentColor)
            Toggle("Verify After Typing", isOn: $vm.automationSettings.verifyFieldValueAfterTyping)
                .tint(accentColor)
            Toggle("Retype On Failure", isOn: $vm.automationSettings.retypeOnVerificationFailure)
                .tint(accentColor)
        } header: {
            Label("Session Management", systemImage: "lock.rectangle.stack.fill")
        }
    }

    // MARK: - MFA

    private var mfaHandlingSection: some View {
        Section {
            Toggle("MFA Detection", isOn: $vm.automationSettings.mfaDetectionEnabled)
                .tint(accentColor)
            if vm.automationSettings.mfaDetectionEnabled {
                Toggle("Auto-Skip MFA", isOn: $vm.automationSettings.mfaAutoSkip)
                    .tint(accentColor)
                Toggle("Mark as Temp Disabled", isOn: $vm.automationSettings.mfaMarkAsTempDisabled)
                    .tint(accentColor)
                Button { showMFAKeywordEditor = true } label: {
                    dfKeywordRow("MFA Keywords", count: vm.automationSettings.mfaKeywords.count)
                }
            }
            Toggle("SMS Detection", isOn: $vm.automationSettings.smsDetectionEnabled)
                .tint(accentColor)
            if vm.automationSettings.smsDetectionEnabled {
                Toggle("SMS Burn Session", isOn: $vm.automationSettings.smsBurnSession)
                    .tint(.red)
            }
        } header: {
            Label("MFA / SMS", systemImage: "lock.shield.fill")
        }
    }

    // MARK: - CAPTCHA

    private var captchaHandlingSection: some View {
        Section {
            Toggle("CAPTCHA Detection", isOn: $vm.automationSettings.captchaDetectionEnabled)
                .tint(accentColor)
            if vm.automationSettings.captchaDetectionEnabled {
                Toggle("Auto-Skip CAPTCHA", isOn: $vm.automationSettings.captchaAutoSkip)
                    .tint(accentColor)
                Toggle("CAPTCHA iFrame Detection", isOn: $vm.automationSettings.captchaIframeDetection)
                    .tint(accentColor)
                Button { showCaptchaKeywordEditor = true } label: {
                    dfKeywordRow("CAPTCHA Keywords", count: vm.automationSettings.captchaKeywords.count)
                }
            }
        } header: {
            Label("CAPTCHA", systemImage: "shield.lefthalf.filled")
        }
    }

    // MARK: - Blank Page Recovery

    private var blankPageRecoverySection: some View {
        Section {
            Toggle("Blank Page Recovery", isOn: $vm.automationSettings.blankPageRecoveryEnabled)
                .tint(accentColor)
            if vm.automationSettings.blankPageRecoveryEnabled {
                Stepper("Timeout: \(vm.automationSettings.blankPageTimeoutSeconds)s", value: $vm.automationSettings.blankPageTimeoutSeconds, in: 5...60, step: 5)
                Stepper("Wait Threshold: \(vm.automationSettings.blankPageWaitThresholdSeconds)s", value: $vm.automationSettings.blankPageWaitThresholdSeconds, in: 30...300, step: 10)
                Toggle("Wait & Recheck", isOn: $vm.automationSettings.blankPageFallback1_WaitAndRecheck)
                    .tint(accentColor)
                Toggle("Change URL", isOn: $vm.automationSettings.blankPageFallback2_ChangeURL)
                    .tint(accentColor)
                Toggle("Change DNS", isOn: $vm.automationSettings.blankPageFallback3_ChangeDNS)
                    .tint(accentColor)
                Toggle("Change Fingerprint", isOn: $vm.automationSettings.blankPageFallback4_ChangeFingerprint)
                    .tint(accentColor)
                Toggle("Full Session Reset", isOn: $vm.automationSettings.blankPageFallback5_FullSessionReset)
                    .tint(accentColor)
            }
        } header: {
            Label("Blank Page Recovery", systemImage: "doc.questionmark.fill")
        }
    }

    // MARK: - Network Per-Mode

    private var networkPerModeSection: some View {
        Section {
            Toggle("Use Assigned Network", isOn: $vm.automationSettings.useAssignedNetworkForTests)
                .tint(accentColor)
            Toggle("Proxy Rotate on Disabled", isOn: $vm.automationSettings.proxyRotateOnDisabled)
                .tint(accentColor)
            Toggle("Proxy Rotate on Failure", isOn: $vm.automationSettings.proxyRotateOnFailure)
                .tint(accentColor)
            Toggle("DNS Rotate Per Request", isOn: $vm.automationSettings.dnsRotatePerRequest)
                .tint(accentColor)
            Toggle("VPN Config Rotation", isOn: $vm.automationSettings.vpnConfigRotation)
                .tint(accentColor)
            Toggle("URL Rotation", isOn: $vm.automationSettings.urlRotationEnabled)
                .tint(accentColor)
            Toggle("Smart URL Selection", isOn: $vm.automationSettings.smartURLSelection)
                .tint(accentColor)
            Toggle("Auto-Blacklist No Acc", isOn: $vm.automationSettings.autoBlacklistNoAcc)
                .tint(accentColor)
            Toggle("Auto-Blacklist Perm Disabled", isOn: $vm.automationSettings.autoBlacklistPermDisabled)
                .tint(accentColor)
        } header: {
            Label("Network & Blacklist", systemImage: "network.badge.shield.half.filled")
        }
    }

    // MARK: - Error Classification

    private var errorClassificationSection: some View {
        Section {
            Toggle("Network Error Auto-Retry", isOn: $vm.automationSettings.networkErrorAutoRetry)
                .tint(accentColor)
            Toggle("SSL Error Auto-Retry", isOn: $vm.automationSettings.sslErrorAutoRetry)
                .tint(accentColor)
            Toggle("HTTP 403 Mark Blocked", isOn: $vm.automationSettings.http403MarkAsBlocked)
                .tint(accentColor)
            Toggle("HTTP 5xx Auto-Retry", isOn: $vm.automationSettings.http5xxAutoRetry)
                .tint(accentColor)
            Toggle("Connection Reset Auto-Retry", isOn: $vm.automationSettings.connectionResetAutoRetry)
                .tint(accentColor)
            Toggle("DNS Failure Auto-Retry", isOn: $vm.automationSettings.dnsFailureAutoRetry)
                .tint(accentColor)
        } header: {
            Label("Error Classification", systemImage: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Helpers

    private func dfSelectorField(_ label: String, placeholder: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: binding)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func dfKeywordRow(_ title: String, count: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(count) configured").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
