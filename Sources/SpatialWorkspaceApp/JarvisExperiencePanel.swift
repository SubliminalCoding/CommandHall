import SwiftUI

enum JarvisExperienceMode: String, CaseIterable, Identifiable {
    case voice
    case barehands
    case particleField

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: "Voice"
        case .barehands: "Barehands"
        case .particleField: "Particle Field"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .barehands: "hand.raised.fingers.spread"
        case .particleField: "sparkles"
        }
    }
}

enum JarvisHandsFreeConversationPolicy {
    static let restartDelayNanoseconds: UInt64 = 450_000_000
    static let retryDelayNanoseconds: UInt64 = 900_000_000

    static func shouldStartListening(
        isJarvisEnabled: Bool,
        isEnabled: Bool,
        voiceState: JarvisVoiceState,
        isRecording: Bool,
        isTranscribing: Bool,
        hasBlockingError: Bool
    ) -> Bool {
        isJarvisEnabled
            && isEnabled
            && voiceState == .idle
            && !isRecording
            && !isTranscribing
            && !hasBlockingError
    }
}

struct JarvisExperiencePanel: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var speech: SpeechController
    @Binding var isPresented: Bool

    @AppStorage("jarvisExperienceMode") private var storedMode = JarvisExperienceMode.voice.rawValue
    @AppStorage("jarvisWakeWordEnabled") private var wakeWordEnabled = true
    @AppStorage("jarvisHandsFreeConversationEnabled") private var handsFreeConversationEnabled = true

    @StateObject private var wake = JarvisWakeController()
    @StateObject private var processingSound = JarvisProcessingSoundController()
    @State private var handsFreeListeningTask: Task<Void, Never>?
    @State private var wakeInterruptionActive = false
    @State private var showsJarvisSettings = false
    @State private var showsVoiceDoctor = false
    @State private var voiceHealthReport: JarvisVoiceHealthReport?
    @State private var voiceDoctorIsRunning = false

    private var selection: Binding<JarvisExperienceMode> {
        Binding(
            get: { JarvisExperienceMode(rawValue: storedMode) ?? .voice },
            set: { storedMode = $0.rawValue }
        )
    }

    var body: some View {
        ZStack {
            switch selection.wrappedValue {
            case .voice:
                JarvisVoicePanel(
                    store: store,
                    speech: speech,
                    isPresented: $isPresented,
                    isVoiceEnabled: store.jarvisVoiceEnabled,
                    showsCloseButton: false
                )
            case .barehands:
                BarehandsJarvisPage(store: store, speech: speech)
            case .particleField:
                HQParticleJarvisPage()
            }

            experienceSwitcher
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                jarvisControlBar
                if showsJarvisSettings {
                    jarvisSettingsPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showsVoiceDoctor {
                    JarvisVoiceDoctorView(
                        report: voiceHealthReport,
                        isRunning: voiceDoctorIsRunning,
                        activeProvider: store.jarvisSpeechProvider,
                        isVoiceEnabled: store.jarvisVoiceEnabled,
                        onRun: runVoiceDoctor,
                        onTest: store.previewCompletionVoice,
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showsVoiceDoctor = false
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 20)
                .padding(.top, 58)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .padding(.top, 14)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel("Close Jarvis")
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .onExitCommand { isPresented = false }
        .onAppear {
            wake.onWake = { [store] in
                guard store.jarvisVoiceEnabled, store.jarvisVoiceState == .speaking else { return }
                wakeInterruptionActive = true
                store.interruptJarvisSpeech()
            }
            wake.onCommand = { [store] command in
                guard store.jarvisVoiceEnabled else { return }
                _ = store.sendToJarvis(command)
                wakeInterruptionActive = false
                reconcileListeningModes()
            }
            wake.onWakeCancelled = {
                wakeInterruptionActive = false
                reconcileListeningModes()
            }
            if !store.jarvisVoiceEnabled { store.stopJarvisVoiceActivity() }
            applyJarvisPowerState(store.jarvisVoiceEnabled)
        }
        .onDisappear {
            handsFreeListeningTask?.cancel()
            handsFreeListeningTask = nil
            wake.setEnabled(false)
            processingSound.stop()
        }
        .onChange(of: wakeWordEnabled) { _, _ in reconcileListeningModes() }
        .onChange(of: handsFreeConversationEnabled) { _, enabled in
            if !enabled, speech.isRecording {
                speech.cancel()
                store.setListening(false)
            }
            reconcileListeningModes()
            if enabled { scheduleHandsFreeListening() }
        }
        .onChange(of: store.jarvisVoiceEnabled) { _, enabled in
            applyJarvisPowerState(enabled)
        }
        .onChange(of: store.jarvisVoiceState) { _, state in
            reconcileListeningModes()
            processingSound.setThinking(store.jarvisVoiceEnabled && state == .thinking)
            if state == .thinking || state == .speaking {
                handsFreeListeningTask?.cancel()
                handsFreeListeningTask = nil
            } else if state == .idle {
                scheduleHandsFreeListening()
            }
        }
        .onChange(of: speech.isRecording) { _, _ in
            updateWakeSuppression(state: store.jarvisVoiceState)
        }
        .onChange(of: speech.isTranscribing) { _, isTranscribing in
            guard !isTranscribing else { return }
            scheduleHandsFreeListening()
        }
        .onChange(of: speech.errorMessage) { _, error in
            guard store.jarvisVoiceEnabled else { return }
            if let error {
                store.reportVoiceFailure(error, retryable: speech.handsFreeRetryAllowed)
                scheduleHandsFreeListening()
            } else {
                store.clearVoiceFailure()
            }
        }
    }

    private func applyJarvisPowerState(_ enabled: Bool) {
        handsFreeListeningTask?.cancel()
        handsFreeListeningTask = nil
        wakeInterruptionActive = false
        if enabled {
            wake.setSuppressed(false)
            reconcileListeningModes()
            processingSound.setThinking(store.jarvisVoiceState == .thinking)
            scheduleHandsFreeListening()
            return
        }

        wake.setSuppressed(true)
        wake.setEnabled(false)
        processingSound.stop()
        withAnimation(.easeOut(duration: 0.16)) {
            showsJarvisSettings = false
            showsVoiceDoctor = false
        }
        if speech.isBusy { speech.cancel() }
    }

    private var jarvisControlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: voiceStatusSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(voiceStatusColor)
                .symbolEffect(
                    .pulse,
                    isActive: store.jarvisVoiceEnabled && (effectiveVoiceState == .listening || effectiveVoiceState == .thinking)
                )
                .frame(width: 30, height: 30)
                .background(voiceStatusColor.opacity(0.13), in: Circle())

            Text("JARVIS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.9))

            Circle()
                .fill(voiceStatusColor)
                .frame(width: 5, height: 5)

            Text(voiceStatusLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(voiceStatusColor)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsJarvisSettings.toggle()
                    if !showsJarvisSettings { showsVoiceDoctor = false }
                }
            } label: {
                Image(systemName: voiceHealthReport?.isReady == false ? "exclamationmark.triangle.fill" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(voiceHealthReport?.isReady == false ? Color.orange : Color.white.opacity(0.62))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(showsJarvisSettings ? 0.10 : 0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help(showsJarvisSettings ? "Close Jarvis settings" : "Jarvis settings")
            .accessibilityLabel(showsJarvisSettings ? "Close Jarvis settings" : "Open Jarvis settings")

            Button {
                store.setJarvisVoiceEnabled(!store.jarvisVoiceEnabled)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(store.jarvisVoiceEnabled ? Color.green : Color.white.opacity(0.46))
                    .frame(width: 30, height: 30)
                    .background(
                        (store.jarvisVoiceEnabled ? Color.green : Color.white).opacity(0.09),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .help(store.jarvisVoiceEnabled ? "Turn Jarvis off" : "Turn Jarvis on")
            .accessibilityLabel(store.jarvisVoiceEnabled ? "Turn Jarvis off" : "Turn Jarvis on")
            .accessibilityValue(store.jarvisVoiceEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 8)
        .frame(width: 340, height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.56), in: Capsule())
        .overlay(Capsule().stroke(voiceStatusColor.opacity(0.2)))
        .shadow(color: .black.opacity(0.26), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jarvis \(voiceStatusLabel.lowercased())")
    }

    private var jarvisSettingsPanel: some View {
        VStack(spacing: 0) {
            settingsToggle(
                "Hands-free",
                systemImage: "arrow.triangle.2.circlepath",
                isOn: $handsFreeConversationEnabled
            )

            Divider().overlay(Color.white.opacity(0.08))

            settingsToggle(
                "Wake word",
                systemImage: wakeWordEnabled ? "mic.fill" : "mic.slash",
                isOn: $wakeWordEnabled
            )

            Divider().overlay(Color.white.opacity(0.08))

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsVoiceDoctor.toggle()
                }
                if showsVoiceDoctor, voiceHealthReport == nil { runVoiceDoctor() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: voiceHealthReport?.isReady == false ? "exclamationmark.triangle.fill" : "stethoscope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(voiceHealthReport?.isReady == false ? Color.orange : Color.white.opacity(0.58))
                        .frame(width: 20)
                    Text("Voice diagnostics")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Spacer()
                    Text(voiceDiagnosticLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(voiceHealthReport?.isReady == false ? Color.orange : Color.white.opacity(0.38))
                    Image(systemName: showsVoiceDoctor ? "chevron.up" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsVoiceDoctor ? "Minimize Jarvis Voice Doctor" : "Open Jarvis Voice Doctor")
        }
        .padding(.horizontal, 12)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    private func settingsToggle(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.cyan)
                .disabled(!store.jarvisVoiceEnabled)
                .accessibilityLabel(title)
        }
        .frame(height: 40)
        .opacity(store.jarvisVoiceEnabled ? 1 : 0.42)
    }

    private func reconcileListeningModes() {
        guard store.jarvisVoiceEnabled else {
            wake.setSuppressed(true)
            wake.setEnabled(false)
            return
        }
        let enablesInterruption = store.jarvisVoiceState == .speaking || wakeInterruptionActive
        wake.setInterruptionMode(enablesInterruption)
        wake.setEnabled(wakeWordEnabled && (!handsFreeConversationEnabled || enablesInterruption))
        updateWakeSuppression(state: store.jarvisVoiceState)
    }

    private func updateWakeSuppression(state: JarvisVoiceState) {
        // Voice processing lets the wake recognizer stay active during playback
        // so “Jarvis, …” can interrupt. It remains off during capture and thought.
        wake.setSuppressed(
            (state == .thinking && !wakeInterruptionActive)
                || speech.isRecording
        )
    }

    private func scheduleHandsFreeListening() {
        handsFreeListeningTask?.cancel()
        handsFreeListeningTask = nil
        guard JarvisHandsFreeConversationPolicy.shouldStartListening(
            isJarvisEnabled: store.jarvisVoiceEnabled,
            isEnabled: handsFreeConversationEnabled,
            voiceState: store.jarvisVoiceState,
            isRecording: speech.isRecording,
            isTranscribing: speech.isTranscribing,
            hasBlockingError: speech.errorMessage != nil && !speech.handsFreeRetryAllowed
        ) else { return }

        handsFreeListeningTask = Task {
            let delay = speech.handsFreeRetryAllowed
                ? JarvisHandsFreeConversationPolicy.retryDelayNanoseconds
                : JarvisHandsFreeConversationPolicy.restartDelayNanoseconds
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  JarvisHandsFreeConversationPolicy.shouldStartListening(
                    isJarvisEnabled: store.jarvisVoiceEnabled,
                    isEnabled: handsFreeConversationEnabled,
                    voiceState: store.jarvisVoiceState,
                    isRecording: speech.isRecording,
                    isTranscribing: speech.isTranscribing,
                    hasBlockingError: speech.errorMessage != nil && !speech.handsFreeRetryAllowed
                  ) else { return }
            let started = await speech.start()
            guard !Task.isCancelled else {
                if started { speech.cancel() }
                return
            }
            store.setListening(started)
            if !started, let error = speech.errorMessage {
                store.supervisorMessage = error
            }
            handsFreeListeningTask = nil
        }
    }

    private var effectiveVoiceState: JarvisVoiceState {
        if speech.isRecording { return .listening }
        if speech.isTranscribing { return .transcribing }
        if speech.errorMessage != nil, store.jarvisVoiceState == .idle { return .error }
        return store.jarvisVoiceState
    }

    private var voiceStatusSymbol: String {
        guard store.jarvisVoiceEnabled else { return "power" }
        return switch effectiveVoiceState {
        case .idle: "waveform"
        case .listening: "waveform.circle.fill"
        case .transcribing: "text.bubble.fill"
        case .thinking: "cpu.fill"
        case .speaking: "speaker.wave.2.fill"
        case .recovering: "arrow.clockwise.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var voiceStatusColor: Color {
        store.jarvisVoiceEnabled ? effectiveVoiceState.hotColor : Color.white.opacity(0.36)
    }

    private var voiceStatusLabel: String {
        store.jarvisVoiceEnabled ? effectiveVoiceState.label.uppercased() : "OFF"
    }

    private var voiceDiagnosticLabel: String {
        if voiceDoctorIsRunning { return "CHECKING" }
        guard let voiceHealthReport else { return "RUN" }
        return voiceHealthReport.isReady ? "READY" : "CHECK"
    }

    private func runVoiceDoctor() {
        guard !voiceDoctorIsRunning else { return }
        voiceDoctorIsRunning = true
        Task {
            let report = await JarvisVoiceDoctor().run()
            voiceHealthReport = report
            voiceDoctorIsRunning = false
        }
    }

    private var experienceSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(JarvisExperienceMode.allCases) { mode in
                let selected = selection.wrappedValue == mode
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection.wrappedValue = mode
                    }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.68))
                        .background(selected ? Color.white.opacity(0.92) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(mode.title) Jarvis experience")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.44), radius: 18, y: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jarvis experience")
    }
}

private struct JarvisVoiceDoctorView: View {
    let report: JarvisVoiceHealthReport?
    let isRunning: Bool
    let activeProvider: JarvisSpeechProvider?
    let isVoiceEnabled: Bool
    let onRun: () -> Void
    let onTest: () -> Void
    let onDismiss: () -> Void

    @AppStorage(JarvisVoiceProviderPreference.defaultsKey)
    private var providerRaw = JarvisVoiceProviderPreference.kokoro.rawValue

    private var provider: Binding<JarvisVoiceProviderPreference> {
        Binding(
            get: { JarvisVoiceProviderPreference(rawValue: providerRaw) ?? .kokoro },
            set: { providerRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Doctor")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(report?.summary ?? "Checking Jarvis from microphone to speaker")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: onRun) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Run voice checks again")
                }
                Button(action: onDismiss) {
                    Image(systemName: "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Minimize Voice Doctor")
                .accessibilityLabel("Minimize Voice Doctor")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Preferred voice")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Picker("Preferred voice", selection: provider) {
                    ForEach(JarvisVoiceProviderPreference.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(provider.wrappedValue.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                if let activeProvider {
                    Text("Last playback: \(activeProvider.label)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }

            Divider()

            if let report {
                VStack(spacing: 8) {
                    ForEach(report.checks) { check in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: healthSymbol(check.state))
                                .foregroundStyle(healthColor(check.state))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(check.title).font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text(check.state.label)
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(healthColor(check.state))
                                }
                                Text(check.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            Button("Test selected voice", action: onTest)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(isRunning || !isVoiceEnabled)
                .help(isVoiceEnabled ? "Play a short Jarvis voice sample" : "Turn Jarvis on to test his voice")
        }
        .padding(18)
        .frame(width: 370)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.44), radius: 20, y: 8)
    }

    private func healthSymbol(_ state: JarvisVoiceHealthState) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .fallback: "arrow.triangle.2.circlepath.circle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }

    private func healthColor(_ state: JarvisVoiceHealthState) -> Color {
        switch state {
        case .ready: .green
        case .fallback: .orange
        case .unavailable: .red
        }
    }
}

private struct BarehandsJarvisPage: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var speech: SpeechController

    @StateObject private var controller = BarehandsServiceController()
    @State private var webState = WebPreviewState.idle
    @State private var showsGestureGuide = false
    @State private var showsClearConfirmation = false
    @State private var showsReloadConfirmation = false
    @State private var jarvisHoldTask: Task<Void, Never>?

    private struct CoachStatus {
        let symbol: String
        let title: String
        let instruction: String
        let color: Color
    }

    var body: some View {
        ZStack {
            Color(red: 0.006, green: 0.009, blue: 0.018).ignoresSafeArea()

            if controller.state == .ready {
                WebPreview(
                    urlString: controller.hostedStageURL.absoluteString,
                    revision: controller.webRevision,
                    state: $webState,
                    allowsLoopbackMediaCapture: true
                )
                .ignoresSafeArea()
            } else {
                serviceState
            }

            if let message = webState.errorMessage, controller.state == .ready {
                webFailure(message)
            }

            if controller.state == .ready {
                trackingStatus
            }

            HStack(spacing: 8) {
                Button("Barehands by Jared Rhodenizer", action: controller.openSourceRepository)
                    .buttonStyle(.plain)
                    .underline()
                Text("AGPL-3.0")
                    .foregroundStyle(.white.opacity(0.38))
                Button(action: requestReload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload Barehands; confirmation protects open board content")
                Button(action: controller.openInBrowser) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.plain)
                .help("Open Barehands in a browser")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.black.opacity(0.62), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10)))
            .padding(.leading, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .confirmationDialog(
            "Clear the Barehands board?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Board", role: .destructive) {
                controller.performBoardCommand(.clearBoard)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears open Barehands content while keeping Jarvis available. The board will offer Undo for 12 seconds.")
        }
        .confirmationDialog(
            "Reload Barehands?",
            isPresented: $showsReloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reload Barehands", role: .destructive) {
                controller.reloadPage()
            }
            Button("Keep Board Open", role: .cancel) {}
        } message: {
            Text(controller.reloadConfirmationMessage)
        }
        .onAppear {
            controller.start()
            syncJarvisRing()
        }
        .onChange(of: controller.trackingSnapshot?.interaction) { _, interaction in
            updateJarvisHold(interaction)
        }
        .onChange(of: speech.autoStopRequested) { _, shouldStop in
            guard shouldStop, speech.isRecording else { return }
            Task { await finishVoiceAndSend() }
        }
        .onChange(of: effectiveVoiceState) { _, _ in syncJarvisRing() }
        .onChange(of: effectiveAudioLevel) { _, _ in syncJarvisRing() }
        .onDisappear {
            jarvisHoldTask?.cancel()
            jarvisHoldTask = nil
            if speech.isRecording {
                speech.cancel()
                store.setListening(false)
            }
            controller.reflectJarvis(state: .idle, audioLevel: 0)
            controller.stop()
        }
        .accessibilityLabel("Barehands Jarvis workspace")
    }

    private var effectiveVoiceState: JarvisVoiceState {
        if speech.isRecording { return .listening }
        if speech.isTranscribing { return .transcribing }
        if speech.errorMessage != nil, store.jarvisVoiceState == .idle { return .error }
        return store.jarvisVoiceState
    }

    private var effectiveAudioLevel: Double {
        speech.isRecording ? speech.inputLevel : store.jarvisAudioLevel
    }

    private var trackingStatus: some View {
        let status = trackingStatusContent
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 24, height: 24)
                    .background(status.color.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(status.instruction)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(communicationHint)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Spacer(minLength: 4)

                Button {
                    showsGestureGuide.toggle()
                } label: {
                    Image(systemName: "questionmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("How to use Barehands")
                .popover(isPresented: $showsGestureGuide, arrowEdge: .bottom) {
                    gestureGuide
                }
            }

            if let coach = controller.trackingSnapshot?.coach {
                coachProgress(coach)
            }

            Divider()
                .overlay(.white.opacity(0.10))

            HStack(spacing: 6) {
                boardActionButton(
                    "Find Jarvis",
                    symbol: "scope",
                    command: .findRing,
                    hint: "Returns the Jarvis ring to center without closing anything"
                )
                boardActionButton(
                    "Fit Board",
                    symbol: "rectangle.inset.filled",
                    command: .fitBoard,
                    hint: "Brings offscreen Barehands items back into view without closing them"
                )
                boardActionButton(
                    "Practice again",
                    symbol: "hand.pinch",
                    command: .restartCoach,
                    hint: "Restarts the five-step gesture coach without changing the board"
                )

                Spacer(minLength: 4)

                if controller.canUndoClear {
                    Button {
                        controller.performBoardCommand(.undoClear)
                    } label: {
                        actionLabel(
                            controller.undoClearSecondsRemaining.map { "Undo \($0)s" } ?? "Undo Clear",
                            symbol: "arrow.uturn.backward",
                            command: .undoClear
                        )
                        .foregroundStyle(Color.green.opacity(0.92))
                    }
                    .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 9))
                    .disabled(!controller.canUndoClear || controller.activeBoardCommand != nil)
                    .accessibilityLabel("Undo Clear Board")
                    .accessibilityHint("Restores the Barehands board before the undo window expires")
                }

                Button {
                    showsClearConfirmation = true
                } label: {
                    actionLabel("Clear", symbol: "trash", command: .clearBoard)
                        .foregroundStyle(Color.red.opacity(0.82))
                }
                .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 9))
                .disabled(!controller.canClearBoard || controller.activeBoardCommand != nil)
                .accessibilityLabel("Clear Barehands Board")
                .accessibilityHint(
                    controller.canClearBoard
                        ? "Asks for confirmation before removing every open Barehands item"
                        : "Unavailable when only the pinned Jarvis ring remains"
                )
            }

            if let message = controller.boardActionMessage {
                Label(
                    message,
                    systemImage: controller.boardActionFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(controller.boardActionFailed ? Color.orange : Color.green)
                .lineLimit(2)
                .accessibilityLabel(message)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: 590, alignment: .leading)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.34), radius: 20, y: 8)
        .padding(.trailing, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Barehands gesture coach and board controls")
    }

    @ViewBuilder
    private func coachProgress(_ coach: BarehandsCoachSnapshot) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Capsule()
                        .fill(index <= min(coach.step.progress, 4) ? Color.cyan.opacity(0.82) : Color.white.opacity(0.13))
                        .frame(width: index <= min(coach.step.progress, 4) ? 18 : 8, height: 4)
                }
            }
            .accessibilityHidden(true)

            Text(coach.completed ? "Practice complete" : "Step \(min(coach.step.progress + 1, 5)) of 5")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            coach.completed
                ? "Gesture practice complete"
                : "Gesture practice step \(min(coach.step.progress + 1, 5)) of 5"
        )
    }

    private func boardActionButton(
        _ title: String,
        symbol: String,
        command: BarehandsBoardCommand,
        hint: String
    ) -> some View {
        Button {
            controller.performBoardCommand(command)
        } label: {
            actionLabel(title, symbol: symbol, command: command)
        }
        .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 9))
        .disabled(!controller.canSendBoardCommands || controller.activeBoardCommand != nil)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private func actionLabel(
        _ title: String,
        symbol: String,
        command: BarehandsBoardCommand
    ) -> some View {
        HStack(spacing: 5) {
            if controller.activeBoardCommand == command {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.cyan)
            } else {
                Image(systemName: symbol)
            }
            Text(controller.activeBoardCommand == command ? command.progressLabel : title)
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.09)))
    }

    private var trackingStatusContent: CoachStatus {
        if speech.isRecording {
            return CoachStatus(
                symbol: "waveform",
                title: "Jarvis is listening",
                instruction: "Speak naturally, then pause. Hold the OK sign on the Jarvis ring again to send now.",
                color: .cyan
            )
        }
        if speech.isTranscribing {
            return CoachStatus(
                symbol: "ellipsis",
                title: "Sending your voice to Jarvis",
                instruction: "Turning your speech into a message.",
                color: .yellow
            )
        }
        if store.jarvisVoiceState == .thinking {
            return CoachStatus(
                symbol: "brain.head.profile",
                title: "Jarvis is thinking",
                instruction: "The ring will answer as soon as the HQ response begins.",
                color: .purple
            )
        }
        if store.jarvisVoiceState == .speaking {
            return CoachStatus(
                symbol: "waveform.circle.fill",
                title: "Jarvis is speaking",
                instruction: "Hold the OK sign on the Jarvis ring to interrupt and ask another question.",
                color: .green
            )
        }
        if controller.trackingSnapshotIsStale {
            return CoachStatus(
                symbol: "video.slash",
                title: "Tracking paused",
                instruction: "Your board is preserved. Wait for tracking to recover; if Barehands was already open during this update, restart its service once.",
                color: .orange
            )
        }
        guard let snapshot = controller.trackingSnapshot else {
            return CoachStatus(
                symbol: "camera",
                title: "Starting camera tracking",
                instruction: "Wait for the Jarvis ring and cyan hand cursor.",
                color: .cyan
            )
        }
        if controller.trackingSnapshotNeedsServiceRestart {
            return CoachStatus(
                symbol: "arrow.triangle.2.circlepath",
                title: "Safe board session unavailable",
                instruction: "This view is receiving an older or different board session. Restart Barehands once, then reopen this view.",
                color: .orange
            )
        }
        guard snapshot.itemCount > 0 else {
            return CoachStatus(
                symbol: "hourglass",
                title: "Loading the board",
                instruction: "Wait for the Jarvis ring to appear.",
                color: .cyan
            )
        }
        if let interaction = snapshot.interaction {
            return status(for: interaction, coach: snapshot.coach)
        }
        if let coach = snapshot.coach {
            return status(for: coach)
        }
        guard snapshot.handCount > 0 else {
            return CoachStatus(
                symbol: "hand.raised",
                title: "Camera on · no hand seen",
                instruction: "Raise one hand fully into the camera frame.",
                color: .orange
            )
        }
        if let target = snapshot.primaryHoverTarget {
            if snapshot.isPinching {
                return CoachStatus(
                    symbol: "hand.pinch",
                    title: "Pinch detected on \(target.title)",
                    instruction: "Release now without moving your hand.",
                    color: .yellow
                )
            }
            return CoachStatus(
                symbol: "scope",
                title: "Target ready · \(target.title)",
                instruction: "Touch thumb and index while keeping the other three fingers open.",
                color: .green
            )
        }
        if snapshot.isPinching {
            return CoachStatus(
                symbol: "hand.pinch",
                title: "Pinch detected",
                instruction: "Move over a Barehands target, then try again.",
                color: .yellow
            )
        }
        let target = snapshot.itemCount == 1 ? "Jarvis ring" : "ring or a Barehands card"
        return CoachStatus(
            symbol: "hand.point.up.left",
            title: "Hand tracking active",
            instruction: "Aim the cyan cursor at the \(target).",
            color: .green
        )
    }

    private func status(
        for interaction: BarehandsInteractionSnapshot,
        coach: BarehandsCoachSnapshot?
    ) -> CoachStatus {
        let target = interaction.target?.title
        switch interaction.phase {
        case .waitingForHand:
            return CoachStatus(
                symbol: "hand.raised",
                title: "Camera ready",
                instruction: reasonInstruction(interaction.reason) ?? "Raise one hand fully into the camera frame.",
                color: .orange
            )
        case .aiming:
            return CoachStatus(
                symbol: "scope",
                title: "Hand found",
                instruction: reasonInstruction(interaction.reason)
                    ?? (target.map { "Aim the cyan cursor at \($0)." } ?? "Aim the cyan cursor at the Jarvis ring."),
                color: .cyan
            )
        case .ready:
            return CoachStatus(
                symbol: "scope",
                title: target.map { "Target ready · \($0)" } ?? "Target ready",
                instruction: reasonInstruction(interaction.reason)
                    ?? "Touch thumb and index while keeping the other three fingers open.",
                color: .green
            )
        case .pinching:
            return CoachStatus(
                symbol: "hand.pinch.fill",
                title: target.map { "Pinch detected · \($0)" } ?? "Pinch detected",
                instruction: reasonInstruction(interaction.reason) ?? "Release now without moving your hand.",
                color: .yellow
            )
        case .activated:
            let ringOpened = interaction.target?.type == "widget"
            return CoachStatus(
                symbol: "checkmark.circle.fill",
                title: ringOpened ? "Menu opened" : target.map { "\($0) opened" } ?? "Gesture accepted",
                instruction: ringOpened
                    ? "Choose Notes or Props. Hold on the ring next time to talk to Jarvis."
                    : "Success. Choose an item or make another gesture.",
                color: .green
            )
        case .rejected:
            return CoachStatus(
                symbol: "arrow.counterclockwise.circle.fill",
                title: "Try that pinch again",
                instruction: reasonInstruction(interaction.reason)
                    ?? status(for: coach ?? BarehandsCoachSnapshot(step: .makeOKSign, completed: false)).instruction,
                color: .orange
            )
        }
    }

    private func status(for coach: BarehandsCoachSnapshot) -> CoachStatus {
        if coach.completed {
            return CoachStatus(
                symbol: "checkmark.circle.fill",
                title: "Barehands ready",
                instruction: "Aim at any Barehands item, then pinch and release.",
                color: .green
            )
        }
        switch coach.step {
        case .showOneHand:
            return CoachStatus(
                symbol: "hand.raised",
                title: "Step 1 · Show one hand",
                instruction: "Raise one hand fully into the camera frame.",
                color: .orange
            )
        case .targetRing:
            return CoachStatus(
                symbol: "scope",
                title: "Step 2 · Find the target",
                instruction: "Aim the cyan cursor at the Jarvis ring.",
                color: .cyan
            )
        case .makeOKSign:
            return CoachStatus(
                symbol: "hand.pinch",
                title: "Step 3 · Make an OK sign",
                instruction: "Touch thumb and index while keeping the other three fingers open.",
                color: .green
            )
        case .release:
            return CoachStatus(
                symbol: "hand.pinch.fill",
                title: "Step 4 · Pinch detected",
                instruction: "Release now without moving your hand.",
                color: .yellow
            )
        case .chooseOrb:
            return CoachStatus(
                symbol: "circle.grid.2x2.fill",
                title: "Step 5 · Menu opened",
                instruction: "Aim at Notes or Props, then pinch and release.",
                color: .green
            )
        case .complete:
            return CoachStatus(
                symbol: "checkmark.circle.fill",
                title: "Practice complete",
                instruction: "Aim at any Barehands item, then pinch and release.",
                color: .green
            )
        }
    }

    private func reasonInstruction(_ reason: BarehandsInteractionReason?) -> String? {
        guard let reason else { return nil }
        switch reason {
        case .noHand:
            return "Raise one hand fully into the camera frame."
        case .noTarget:
            return "Aim the cyan cursor at the Jarvis ring or another Barehands item."
        case .moveSlower:
            return "Move more slowly as you make the OK sign."
        case .holdOKSign:
            return "Keep thumb and index touching, with the other three fingers open."
        case .releaseQuickly:
            return "Release thumb and index now."
        case .movedTooFar:
            return "Keep your hand steady over the target while pinching."
        case .heldTooLong:
            return "Use a quick pinch and release instead of holding."
        case .trackingLost:
            return "Bring your full hand back into the camera frame."
        case .targetChanged:
            return "Keep the cursor over one target until you release."
        case .gestureUnstable:
            return "Turn your palm toward the camera and hold your fingers steady."
        case .actionComplete:
            return "Gesture accepted."
        case .useOneHand:
            return "Use one hand while learning this gesture."
        }
    }

    private var gestureGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Using Barehands")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Label("Raise one hand until its cursor follows your fingers.", systemImage: "hand.raised")
            Label("Move that cursor over the large Jarvis ring.", systemImage: "scope")
            Label(
                "Make an OK sign: touch thumb to index while the other three fingers stay open, then release quickly.",
                systemImage: "hand.pinch"
            )
            Label("Hold the OK sign on the Jarvis ring until it starts listening. Hold again to send immediately, or pause when you finish speaking.", systemImage: "waveform")
            Label("Choose Notes or Props with the same pinch-and-release gesture.", systemImage: "circle.grid.2x2")
            Text("Barehands controls this board and the Jarvis voice channel. It does not click Workspace navigation, terminals, or other app controls.")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(18)
        .frame(width: 360, alignment: .leading)
    }

    private var communicationHint: String {
        if let error = controller.assistantBridgeError { return error }
        if let error = speech.errorMessage { return error }
        return switch effectiveVoiceState {
        case .idle: "Hold the OK sign on Jarvis to talk"
        case .listening: "Listening · pause to send"
        case .transcribing: "Turning speech into a message"
        case .thinking: "Connected to HQ Jarvis"
        case .speaking: "Jarvis voice is live"
        case .recovering: "Restoring the Jarvis voice channel"
        case .error: "Jarvis voice needs attention"
        }
    }

    private func syncJarvisRing() {
        controller.reflectJarvis(state: effectiveVoiceState, audioLevel: effectiveAudioLevel)
    }

    private func updateJarvisHold(_ interaction: BarehandsInteractionSnapshot?) {
        jarvisHoldTask?.cancel()
        jarvisHoldTask = nil
        guard BarehandsJarvisCommunication.isRingHold(interaction) else { return }

        jarvisHoldTask = Task {
            try? await Task.sleep(nanoseconds: BarehandsJarvisCommunication.holdDurationNanoseconds)
            guard !Task.isCancelled,
                  BarehandsJarvisCommunication.isRingHold(controller.trackingSnapshot?.interaction) else { return }
            await toggleJarvisVoice()
            jarvisHoldTask = nil
        }
    }

    private func toggleJarvisVoice() async {
        if speech.isRecording {
            await finishVoiceAndSend()
            return
        }
        guard !speech.isTranscribing else { return }
        if store.jarvisVoiceState == .thinking || store.jarvisVoiceState == .speaking {
            store.interruptJarvisSpeech()
        }

        let started = await speech.start()
        store.setListening(started)
        syncJarvisRing()
        if !started, let error = speech.errorMessage {
            store.supervisorMessage = error
        }
    }

    private func finishVoiceAndSend() async {
        guard speech.isRecording else { return }
        store.setListening(false)
        store.setTranscribing(true)
        let contextTerms = ["Jarvis", "Barehands", store.activeWorkspace.name]
            + store.activeWorkspace.nodes.filter { $0.kind == .agent }.map(\.title)
        guard let transcript = await speech.stopAndTranscribe(contextTerms: contextTerms) else {
            store.setTranscribing(false)
            store.supervisorMessage = speech.errorMessage ?? "Voice message was not captured"
            syncJarvisRing()
            return
        }
        store.setTranscribing(false)
        guard store.sendToJarvis(transcript) else {
            store.supervisorMessage = "Jarvis could not accept the voice message"
            return
        }
        syncJarvisRing()
    }

    private var serviceState: some View {
        VStack(spacing: 14) {
            if controller.state == .checking || controller.state == .starting {
                ProgressView().controlSize(.small).tint(.cyan)
            } else {
                Image(systemName: controller.state == .missing ? "square.and.arrow.down" : "hand.raised.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.cyan)
            }
            Text(controller.state.label)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(controller.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if controller.state == .missing {
                Text("Set COMMANDHALL_BAREHANDS_PATH to use a different checkout")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if controller.state != .checking && controller.state != .starting {
                Button("Try again", action: controller.reconnect)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
            }
        }
        .padding(28)
        .frame(maxWidth: 400)
        .workspaceGlassPanel(cornerRadius: 20, tintOpacity: 0.75, shadowRadius: 28)
    }

    private func webFailure(_ message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Barehands did not load")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reload", action: requestReload)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .workspaceGlassPanel(cornerRadius: 18, tintOpacity: 0.80, shadowRadius: 24)
    }

    private func requestReload() {
        if controller.reloadRequiresConfirmation {
            showsReloadConfirmation = true
        } else {
            controller.reloadPage()
        }
    }
}

private struct HQParticleJarvisPage: View {
    @StateObject private var controller = HQParticleServiceController()
    @State private var webState = WebPreviewState.idle

    private let launchParticleField = #"""
        (() => {
          const preferenceKey = 'hq-voice-viz-mode-v3';
          if (window.localStorage.getItem(preferenceKey) !== 'swarm' &&
              window.sessionStorage.getItem('spatial-swarm-reload') !== '1') {
            window.localStorage.setItem(preferenceKey, 'swarm');
            window.sessionStorage.setItem('spatial-swarm-reload', '1');
            window.location.reload();
            return;
          }
          window.sessionStorage.removeItem('spatial-swarm-reload');
          const style = document.createElement('style');
          style.textContent = '[role="dialog"] > .absolute.right-5.top-5 button:first-child, [role="dialog"] > .absolute.right-5.top-5 button:last-child { display: none !important; }';
          document.head.appendChild(style);
          const open = () => {
            const trigger = Array.from(document.querySelectorAll('button'))
              .find((button) => button.textContent.trim() === 'Visualize');
            if (trigger) trigger.click();
            else window.setTimeout(open, 250);
          };
          open();
        })();
        """#

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if controller.state == .ready {
                WebPreview(
                    urlString: controller.configuration.voiceURL.absoluteString,
                    revision: controller.webRevision,
                    state: $webState,
                    initialJavaScript: launchParticleField,
                    allowsLoopbackMediaCapture: true
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.cyan)
                    if controller.state == .checking || controller.state == .startingRemote || controller.state == .openingTunnel {
                        ProgressView().controlSize(.small).tint(.cyan)
                    }
                    Text(controller.state.label)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(controller.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if case .failed = controller.state {
                        Button("Reconnect HQ", action: controller.reconnect)
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                    }
                }
                .padding(28)
                .frame(maxWidth: 430)
                .workspaceGlassPanel(cornerRadius: 20, tintOpacity: 0.82, shadowRadius: 28)
            }

            if let message = webState.errorMessage, controller.state == .ready {
                Button(action: controller.reloadPage) {
                    Label("Reload particle view", systemImage: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange.opacity(0.86))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Color.black.opacity(0.64), in: Capsule())
                .overlay(Capsule().stroke(.orange.opacity(0.30)))
                .help(message)
                .padding(.trailing, 18)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            Text("HQ · 1,048,576 GPU PARTICLES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.44))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.09)))
                .padding(.leading, 18)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .background(Color.black)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .accessibilityLabel("HQ million-particle Jarvis visualizer")
    }
}
