import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case workspace
    case stage
    case jarvis
    case vtuber
    case obs
    case signalDeck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .stage: "The Stage"
        case .jarvis: "Jarvis"
        case .vtuber: "VTuber"
        case .obs: "OBS"
        case .signalDeck: "Signal Deck"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "square.grid.2x2"
        case .stage: "theatermasks.fill"
        case .jarvis: "waveform.circle.fill"
        case .vtuber: "person.crop.rectangle.fill"
        case .obs: "dot.radiowaves.left.and.right"
        case .signalDeck: "waveform.path.ecg.rectangle"
        }
    }

    var shortcut: String {
        switch self {
        case .workspace: "⌘1"
        case .stage: "⌘2"
        case .jarvis: "⌘3"
        case .vtuber: "⌘4"
        case .obs: "⌘5"
        case .signalDeck: "⌘6"
        }
    }
}

struct AppPageNavigation: View {
    @Binding var selection: AppPage
    var signalDeckState: SignalDeckConnectionState = .idle
    var signalDeckIsAuthoritative = false
    var signalDeckAudioGraphApplied = false
    var compact = false

    var body: some View {
        Menu {
            ForEach(AppPage.allCases) { page in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = page
                    }
                } label: {
                    Label {
                        Text("\(page.title)  \(page.shortcut)")
                    } icon: {
                        Image(systemName: selection == page ? "checkmark" : page.symbol)
                    }
                }
                .accessibilityLabel("Open \(page.title)")
                .accessibilityValue(accessibilityValue(for: page))
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selection.symbol)
                    .font(.system(size: 11, weight: .semibold))
                if !compact {
                    Text(selection.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                if selection == .signalDeck {
                    Circle()
                        .fill(signalDeckColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, compact ? 9 : 11)
            .frame(height: 30)
            .contentShape(Capsule())
            .workspaceHoverCallout(
                "Choose view · \(selection.shortcut)",
                anchorSize: 30,
                placement: .below
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Current view")
        .accessibilityValue(accessibilityValue(for: selection))
        .background(.ultraThinMaterial, in: Capsule())
        .background(WorkspaceVisualStyle.panelTint.opacity(0.48), in: Capsule())
        .overlay(Capsule().stroke(WorkspaceVisualStyle.panelBorder))
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    }

    private var signalDeckColor: Color {
        if signalDeckState == .connected, signalDeckIsAuthoritative {
            return signalDeckAudioGraphApplied ? .green : .orange
        }
        if signalDeckState == .connecting || signalDeckState == .reconnecting { return .yellow }
        return .red
    }

    private func accessibilityValue(for page: AppPage) -> String {
        var values: [String] = []
        if selection == page { values.append("Selected") }
        if page == .signalDeck {
            values.append("SignalDeck \(signalDeckState.label)")
            if signalDeckState == .connected, signalDeckIsAuthoritative, !signalDeckAudioGraphApplied {
                values.append("configuration only")
            }
        }
        return values.joined(separator: ", ")
    }
}
