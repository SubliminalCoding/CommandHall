import AppKit
import SwiftUI

enum JarvisVoiceState: String, Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case recovering
    case error

    var label: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .recovering: "Recovering"
        case .error: "Needs attention"
        }
    }

    var hotColor: Color {
        switch self {
        case .idle: Color(red: 0.38, green: 0.65, blue: 0.98)
        case .listening: Color(red: 0.13, green: 0.83, blue: 0.93)
        case .transcribing: Color(red: 0.20, green: 0.72, blue: 0.98)
        case .thinking: Color(red: 0.75, green: 0.52, blue: 0.98)
        case .speaking: Color(red: 0.98, green: 0.75, blue: 0.14)
        case .recovering: Color(red: 0.98, green: 0.55, blue: 0.16)
        case .error: Color(red: 0.97, green: 0.44, blue: 0.44)
        }
    }

    fileprivate var coolColor: Color {
        switch self {
        case .idle: Color(red: 0.08, green: 0.20, blue: 0.50)
        case .listening: Color(red: 0.03, green: 0.34, blue: 0.42)
        case .transcribing: Color(red: 0.03, green: 0.22, blue: 0.46)
        case .thinking: Color(red: 0.29, green: 0.10, blue: 0.55)
        case .speaking: Color(red: 0.45, green: 0.20, blue: 0.02)
        case .recovering: Color(red: 0.43, green: 0.16, blue: 0.02)
        case .error: Color(red: 0.39, green: 0.05, blue: 0.05)
        }
    }
}

struct JarvisVoiceVisualizer: View {
    var state: JarvisVoiceState
    var audioLevel: Double
    var silenceProgress = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                draw(in: &context, size: size, date: timeline.date)
            }
        }
        .background {
            RadialGradient(
                colors: [state.coolColor.opacity(0.22), Color.black.opacity(0.94)],
                center: .center,
                startRadius: 20,
                endRadius: 620
            )
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shortSide = max(1, min(size.width, size.height))
        let level = min(max(audioLevel, 0), 1)
        let time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
        let coreRadius = min(shortSide * 0.145, 142)

        context.blendMode = .plusLighter
        drawBloom(in: &context, center: center, radius: coreRadius, level: level, time: time)
        drawParticleShell(in: &context, center: center, radius: coreRadius, level: level, time: time)
        drawEnergyCore(in: &context, center: center, radius: coreRadius, level: level, time: time)
        drawEndpointRing(in: &context, center: center, radius: coreRadius)
    }

    private func drawBloom(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        level: Double,
        time: Double
    ) {
        let breath = reduceMotion ? 1 : 1 + CGFloat(sin(time * 0.72)) * 0.025
        let bloomRadius = radius * (2.25 + CGFloat(level) * 0.46) * breath
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - bloomRadius,
                y: center.y - bloomRadius,
                width: bloomRadius * 2,
                height: bloomRadius * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    state.hotColor.opacity(0.21 + level * 0.13),
                    state.coolColor.opacity(0.07),
                    .clear,
                ]),
                center: center,
                startRadius: radius * 0.55,
                endRadius: bloomRadius
            )
        )
    }

    private func drawParticleShell(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        level: Double,
        time: Double
    ) {
        let count = 1_150
        let speed = state == .thinking ? 0.42 : (state == .listening ? -0.20 : 0.11)
        let rotation = reduceMotion ? 0 : time * speed
        let goldenAngle = Double.pi * (3 - sqrt(5.0))
        for index in 0 ..< count {
            let fraction = (Double(index) + 0.5) / Double(count)
            let sphereY = 1 - 2 * fraction
            let radial = sqrt(max(0, 1 - sphereY * sphereY))
            let angle = goldenAngle * Double(index)
            let rawX = cos(angle) * radial
            let rawZ = sin(angle) * radial
            let x = rawX * cos(rotation) - rawZ * sin(rotation)
            let z = rawX * sin(rotation) + rawZ * cos(rotation)
            let seed = hash(Double(index) * 19.19)
            let shell = radius * (1.46 + CGFloat(seed) * 0.82) * (1 + CGFloat(level) * 0.16)
            let perspective = 0.83 + CGFloat(z) * 0.18
            let turbulence = state == .thinking ? sin(time * 2.4 + seed * 31) * 0.12 : 0
            let point = CGPoint(
                x: center.x + CGFloat(x + turbulence) * shell * perspective,
                y: center.y + CGFloat(sphereY) * shell * perspective
            )
            let depth = (z + 1) / 2
            let diameter = (0.75 + seed * 1.65) * (0.78 + depth * 0.66) * (1 + level * 0.62)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)),
                with: .color(state.hotColor.opacity(0.12 + depth * 0.48 + level * 0.13))
            )
        }
    }

    private func drawEnergyCore(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        level: Double,
        time: Double
    ) {
        let turbulence: Double = switch state {
        case .idle: 0.025
        case .listening: 0.05
        case .transcribing: 0.065
        case .thinking: 0.105
        case .speaking: 0.075
        case .recovering: 0.035
        case .error: 0.012
        }
        var shape = Path()
        let segments = 180
        for index in 0 ... segments {
            let angle = Double(index) / Double(segments) * .pi * 2
            let noise = sin(angle * 3.1 + time * 0.7)
                + sin(angle * 7.0 - time * 1.15) * 0.46
                + sin(angle * 13.0 + time * 1.9) * 0.20
            let voice = sin(angle * 9 - time * 5.8) * level * 0.055
            let r = radius * (1 + CGFloat(noise * turbulence + voice))
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            index == 0 ? shape.move(to: point) : shape.addLine(to: point)
        }
        shape.closeSubpath()
        context.fill(
            shape,
            with: .radialGradient(
                Gradient(colors: [
                    state.hotColor.opacity(0.96),
                    state.coolColor.mix(with: state.hotColor, amount: 0.32).opacity(0.96),
                    state.coolColor.opacity(0.98),
                ]),
                center: CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.31),
                startRadius: 1,
                endRadius: radius * 1.38
            )
        )
        context.stroke(shape, with: .color(state.hotColor.opacity(0.82)), lineWidth: 1.1 + level * 1.7)

        // Fine moving ridges make the surface read as energy, not a flat disc.
        for band in 0 ..< 14 {
            let bandY = -0.78 + Double(band) * 0.12
            var ridge = Path()
            for step in 0 ... 64 {
                let x = -0.9 + Double(step) / 64 * 1.8
                let envelope = sqrt(max(0, 1 - x * x))
                let y = bandY * envelope + sin(x * 14 + time * 1.6 + Double(band)) * (0.018 + level * 0.035)
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                step == 0 ? ridge.move(to: point) : ridge.addLine(to: point)
            }
            context.stroke(ridge, with: .color(state.hotColor.opacity(0.075 + level * 0.055)), lineWidth: 0.65)
        }
    }

    private func drawEndpointRing(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard state == .listening, silenceProgress > 0.01 else { return }
        let progress = min(max(silenceProgress, 0), 1)
        let ringRadius = radius * (1.38 - CGFloat(progress) * 0.28)
        let rect = CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(state.hotColor.opacity(0.30)), lineWidth: 5)
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(state.hotColor.opacity(0.96)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [CGFloat(progress) * ringRadius * .pi * 2, ringRadius * .pi * 2])
        )
    }

    private func hash(_ value: Double) -> Double {
        let raw = sin(value) * 43_758.5453
        return raw - floor(raw)
    }
}

struct JarvisVoicePanel: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var speech: SpeechController
    @Binding var isPresented: Bool
    var isVoiceEnabled = true
    var showsCloseButton = true

    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var voiceState: JarvisVoiceState {
        if speech.isRecording { return .listening }
        if speech.isTranscribing { return .transcribing }
        if speech.errorMessage != nil, store.jarvisVoiceState == .idle { return .error }
        return store.jarvisVoiceState
    }

    private var level: Double {
        speech.isRecording ? speech.inputLevel : store.jarvisAudioLevel
    }

    var body: some View {
        ZStack {
            JarvisVoiceVisualizer(
                state: voiceState,
                audioLevel: level,
                silenceProgress: speech.silenceProgress
            )
                .opacity(isVoiceEnabled ? 1 : 0.32)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showsCloseButton {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(WorkspacePressButtonStyle())
                        .accessibilityLabel("Close Jarvis voice room")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }

                Spacer()

                Button {
                    Task { await toggleVoice() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 310, height: 310)
                        VStack(spacing: 9) {
                            Image(systemName: primaryVoiceSymbol)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolEffect(.pulse, isActive: speech.isRecording || speech.isTranscribing)
                                .foregroundStyle(voiceAccent)
                                .frame(width: 46, height: 46)
                                .background(.black.opacity(0.32), in: Circle())
                                .overlay(Circle().stroke(voiceAccent.opacity(0.42)))
                            Text(primaryVoiceAction)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2.2)
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .disabled(!isVoiceEnabled || speech.isTranscribing)
                .accessibilityLabel(primaryVoiceAction.capitalized)

                VStack(spacing: 7) {
                    Text(isVoiceEnabled ? voiceState.label.uppercased() : "OFF")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(3.2)
                        .foregroundStyle(voiceAccent.opacity(0.9))
                    Text(statusDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.44))
                    if speech.isRecording, !speech.partialTranscript.isEmpty {
                        Text(speech.partialTranscript)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                            .accessibilityLabel("Live transcript: \(speech.partialTranscript)")
                    } else if !speech.transcript.isEmpty {
                        HStack(spacing: 8) {
                            Text("Heard: “\(speech.transcript)”")
                                .lineLimit(2)
                            if let confidence = speech.transcriptConfidence {
                                Text("\(Int(confidence * 100))%")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(confidence >= 0.72 ? Color.green : Color.orange)
                            }
                            Button("Correct") {
                                draft = speech.transcript
                                draftFocused = true
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(voiceAccent)
                            .disabled(!isVoiceEnabled)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .frame(maxWidth: 680)
                    }
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    Button {
                        Task { await toggleVoice() }
                    } label: {
                        Image(systemName: speech.isTranscribing ? "ellipsis" : (speech.isRecording ? "stop.fill" : "mic.fill"))
                            .symbolEffect(.pulse, isActive: speech.isRecording)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(speech.isRecording ? .black : .white)
                            .background(speech.isRecording ? voiceAccent : .white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .disabled(!isVoiceEnabled || speech.isTranscribing)
                    .accessibilityLabel(speech.isRecording ? "Stop and send to Jarvis" : "Talk to Jarvis")

                    TextField(isVoiceEnabled ? "Ask Jarvis anything…" : "Turn Jarvis on to talk", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1 ... 4)
                        .focused($draftFocused)
                        .onSubmit(sendDraft)
                        .disabled(!isVoiceEnabled)

                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.black)
                            .background(voiceAccent, in: Circle())
                    }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .disabled(!isVoiceEnabled || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.isTranscribing)
                    .accessibilityLabel(voiceState == .thinking || voiceState == .speaking ? "Replace the current Jarvis turn" : "Send to Jarvis")
                }
                .padding(10)
                .frame(maxWidth: 680)
                .workspaceGlassPanel(cornerRadius: 22, tintOpacity: 0.72, shadowRadius: 24)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            identityHUD
                .padding(.leading, 20)
                .padding(.bottom, 106)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .foregroundStyle(.white)
        .onExitCommand { isPresented = false }
        .onChange(of: speech.autoStopRequested) { _, shouldStop in
            guard store.jarvisVoiceEnabled, shouldStop, speech.isRecording else { return }
            Task { await finishVoiceAndSend() }
        }
        .onDisappear {
            if speech.isRecording {
                speech.cancel()
                store.setListening(false)
            }
        }
    }

    private var identityHUD: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("JARVIS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                Text("HQ memory · Obsidian")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.44))
            }
            Divider()
                .frame(height: 24)
                .overlay(.white.opacity(0.12))
            Label(
                "\(store.activeWorkspace.nodes.filter { $0.kind == .agent }.count) agents",
                systemImage: "dot.radiowaves.left.and.right"
            )
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.black.opacity(0.46), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jarvis, HQ memory and Obsidian, \(store.activeWorkspace.nodes.filter { $0.kind == .agent }.count) agents in view")
    }

    private var statusDetail: String {
        guard isVoiceEnabled else { return "Turn Jarvis on using the power control" }
        if speech.isTranscribing { return "Turning your voice into a message…" }
        if let error = speech.errorMessage { return error }
        return switch voiceState {
        case .idle: "Tap the orb, speak naturally, then pause"
        case .listening: speech.silenceProgress > 0.04 ? "Got it. Sending when the ring closes" : "I’m listening · pause when you’re done"
        case .transcribing: "Turning your speech into a message"
        case .thinking: "Reviewing your request and every live workspace session"
        case .speaking: "Say “Hey Jarvis” or tap the orb to interrupt"
        case .recovering: store.jarvisConversation.detail
        case .error: "Voice input needs attention"
        }
    }

    private var primaryVoiceSymbol: String {
        guard isVoiceEnabled else { return "power" }
        if speech.isTranscribing { return "ellipsis" }
        if speech.isRecording || voiceState == .thinking || voiceState == .speaking { return "stop.fill" }
        return "mic.fill"
    }

    private var primaryVoiceAction: String {
        guard isVoiceEnabled else { return "Jarvis is off" }
        if speech.isRecording { return "Tap to send now" }
        if voiceState == .thinking || voiceState == .speaking { return "Tap to interrupt" }
        return "Tap to talk"
    }

    private func sendDraft() {
        guard store.jarvisVoiceEnabled else { return }
        let request = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let accepted = if store.jarvisVoiceState == .thinking || store.jarvisVoiceState == .speaking {
            store.replaceJarvisTurn(with: request)
        } else {
            store.sendToJarvis(request)
        }
        guard accepted else { return }
        draft = ""
    }

    private func toggleVoice() async {
        guard store.jarvisVoiceEnabled else { return }
        if speech.isRecording {
            await finishVoiceAndSend()
            return
        }

        if store.jarvisVoiceState == .thinking || store.jarvisVoiceState == .speaking {
            store.interruptJarvisSpeech()
        }

        let started = await speech.start()
        store.setListening(started)
        if !started, let error = speech.errorMessage {
            store.supervisorMessage = error
        }
    }

    private func finishVoiceAndSend() async {
        guard store.jarvisVoiceEnabled, speech.isRecording else { return }
        store.setListening(false)
        store.setTranscribing(true)
        let contextTerms = ["Jarvis", store.activeWorkspace.name]
            + store.activeWorkspace.nodes.filter { $0.kind == .agent }.map(\.title)
        guard let transcript = await speech.stopAndTranscribe(contextTerms: contextTerms) else {
            store.setTranscribing(false)
            store.supervisorMessage = speech.errorMessage ?? "Voice message was not captured"
            return
        }
        guard store.jarvisVoiceEnabled else {
            store.setTranscribing(false)
            return
        }
        store.setTranscribing(false)
        draft = transcript
        sendDraft()
    }

    private var voiceAccent: Color {
        isVoiceEnabled ? voiceState.hotColor : Color.white.opacity(0.34)
    }
}

private extension Color {
    func mix(with other: Color, amount: Double) -> Color {
        let value = min(max(amount, 0), 1)
        let base = NSColor(self)
        return Color(nsColor: base.blended(withFraction: value, of: NSColor(other)) ?? base)
    }
}
