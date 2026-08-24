import AppKit
import SwiftUI

struct TerminalPane: View {
    @ObservedObject var session: TerminalSession
    let workingFolderLabel: String?
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @State private var pasteMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: TerminalSession, workingFolderLabel: String? = nil) {
        self.session = session
        self.workingFolderLabel = workingFolderLabel
    }

    var body: some View {
        ZStack {
            TerminalGlassBackdrop(isActive: isRunning && !reduceMotion, accent: statusColor)

            VStack(spacing: 0) {
                shellHeader

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.13), statusColor.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(TerminalTypography.attributed(
                            session.output.isEmpty ? "Booting interactive zsh…" : session.output,
                            size: 12.5
                        ))
                            .lineSpacing(2.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 13)
                            .id("terminal-end")
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: session.output) { _, _ in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            proxy.scrollTo("terminal-end", anchor: .bottom)
                        }
                    }
                }

                commandDock
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { resize(to: proxy.size) }
                    .onChange(of: proxy.size) { _, size in resize(to: size) }
            }
        }
        .accessibilityLabel("Interactive terminal")
    }

    private var shellHeader: some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.36))
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.28))
                Circle().fill(Color(red: 0.35, green: 0.82, blue: 0.42))
            }
            .frame(width: 39)

            Image(systemName: "terminal.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(statusColor)

            Text("zsh")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))

            Text(workingDirectoryLabel)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: statusColor.opacity(isRunning ? 0.85 : 0), radius: 5)
                Text(stateDetail.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.55)
            }
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(0.045), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.07)))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial.opacity(0.18))
    }

    private var commandDock: some View {
        HStack(spacing: 8) {
            Text("❯")
                .font(.custom(TerminalTypography.fontName, fixedSize: 14).weight(.bold))
                .foregroundStyle(statusColor)
                .shadow(color: statusColor.opacity(inputFocused ? 0.55 : 0.18), radius: 5)

            TextField("Type a command…", text: $input)
                .textFieldStyle(.plain)
                .font(.custom(TerminalTypography.fontName, fixedSize: 12.5).weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .focused($inputFocused)
                .onSubmit(submit)
                .onChange(of: inputFocused) { _, focused in
                    if focused { installPasteMonitor() } else { removePasteMonitor() }
                }
                .onDisappear { removePasteMonitor() }

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(canSubmit ? Color.black.opacity(0.82) : .white.opacity(0.25))
                    .frame(width: 25, height: 25)
                    .background(canSubmit ? statusColor : .white.opacity(0.04), in: Circle())
                    .shadow(color: canSubmit ? statusColor.opacity(0.34) : .clear, radius: 8)
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .disabled(!canSubmit)
            .accessibilityLabel("Run command")
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(.ultraThinMaterial.opacity(0.25), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(inputFocused ? statusColor.opacity(0.48) : .white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: inputFocused ? statusColor.opacity(0.12) : .clear, radius: 12)
        .padding(.horizontal, 10)
        .padding(.bottom, 9)
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isRunning
    }

    private var isRunning: Bool {
        if case .running = session.state { return true }
        return false
    }

    private var statusColor: Color {
        switch session.state {
        case .idle: .white.opacity(0.42)
        case .running: Color(red: 0.43, green: 0.94, blue: 0.82)
        case .exited(let code): code == 0 ? Color(red: 0.5, green: 0.9, blue: 0.58) : .orange
        case .failed: Color(red: 1.0, green: 0.42, blue: 0.46)
        }
    }

    private var stateDetail: String {
        switch session.state {
        case .running(let pid): "live · \(pid)"
        default: stateLabel
        }
    }

    private var workingDirectoryLabel: String {
        if let workingFolderLabel { return workingFolderLabel }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = session.workingDirectory.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func submit() {
        guard canSubmit else { return }
        session.send(input + "\r")
        input = ""
    }

    /// Paste support for the command line, on both ⌘V and ⌃V:
    ///  • an image on the clipboard (a screenshot) is saved to a file and its
    ///    path is dropped onto the line, so a CLI agent can read it;
    ///  • ⌃V also pastes text (macOS doesn't natively), so text snippets work;
    ///  • ⌘V with text falls through to the field's native paste (best cursor
    ///    behavior), so nothing regresses.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isV = event.charactersIgnoringModifiers?.lowercased() == "v"
            let cmd = event.modifierFlags.contains(.command)
            let ctrl = event.modifierFlags.contains(.control)
            guard isV, cmd || ctrl, inputFocused else { return event }

            if let path = TerminalImagePaste.pastedImagePath() {
                if !input.isEmpty && !input.hasSuffix(" ") { input += " " }
                input += path + " "
                return nil // handled — don't also run native paste
            }
            if ctrl, !cmd, let text = NSPasteboard.general.string(forType: .string) {
                input += text
                return nil
            }
            return event // ⌘V text → native paste
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .idle: "idle"
        case .running: "live"
        case .exited(let code): "exit \(code)"
        case .failed: "failed"
        }
    }

    private func resize(to size: CGSize) {
        let columns = UInt16(max(10, min(300, Int(size.width / 7.2))))
        let rows = UInt16(max(2, min(120, Int((size.height - 72) / 16))))
        session.resize(columns: columns, rows: rows)
    }
}

private struct TerminalGlassBackdrop: View {
    let isActive: Bool
    let accent: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isActive)) { timeline in
            GeometryReader { geometry in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.075, blue: 0.105).opacity(reduceTransparency ? 0.96 : 0.7),
                            Color(red: 0.012, green: 0.026, blue: 0.052).opacity(reduceTransparency ? 0.98 : 0.76),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(accent.opacity(isActive ? 0.16 : 0.08))
                        .frame(width: geometry.size.width * 0.65)
                        .blur(radius: 48)
                        .offset(
                            x: geometry.size.width * 0.34 + CGFloat(sin(time * 0.15)) * 24,
                            y: -geometry.size.height * 0.35
                        )

                    Canvas { context, size in
                        var grid = Path()
                        let drift = isActive ? CGFloat(time * 3).truncatingRemainder(dividingBy: 24) : 0
                        var x = drift - 24
                        while x < size.width {
                            grid.move(to: CGPoint(x: x, y: 0))
                            grid.addLine(to: CGPoint(x: x, y: size.height))
                            x += 32
                        }
                        var y = drift - 24
                        while y < size.height {
                            grid.move(to: CGPoint(x: 0, y: y))
                            grid.addLine(to: CGPoint(x: size.width, y: y))
                            y += 24
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
