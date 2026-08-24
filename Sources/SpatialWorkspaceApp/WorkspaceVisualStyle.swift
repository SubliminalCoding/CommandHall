import SwiftUI

enum WorkspaceVisualStyle {
    static let accent = Color(red: 0.79, green: 0.89, blue: 0.66)
    static let cyan = Color(red: 0.47, green: 0.86, blue: 0.88)
    static let claude = Color(red: 0.95, green: 0.43, blue: 0.24)
    static let codex = Color(red: 0.20, green: 0.84, blue: 0.57)
    static let browser = Color(red: 0.31, green: 0.67, blue: 1.0)
    static let jarvis = Color(red: 0.77, green: 0.56, blue: 1.0)
    static let panelTint = Color(red: 0.018, green: 0.047, blue: 0.09)
    static let subtleBorder = Color.white.opacity(0.12)

    static let panelBorder = LinearGradient(
        colors: [.white.opacity(0.28), .white.opacity(0.06)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension SessionProvider {
    /// Provider identity color used only as a supporting cue; labels remain visible
    /// so sessions are never distinguished by color alone.
    var workspaceAccent: Color? {
        switch self {
        case .claude: WorkspaceVisualStyle.claude
        case .codex: WorkspaceVisualStyle.codex
        case .browser: WorkspaceVisualStyle.browser
        case .jarvis: WorkspaceVisualStyle.jarvis
        default: nil
        }
    }
}

struct WorkspaceGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tintOpacity = 0.62
    var shadowRadius: CGFloat = 18
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .background(WorkspaceVisualStyle.panelTint.opacity(reduceTransparency ? 0.96 : tintOpacity), in: shape)
            .overlay(shape.stroke(WorkspaceVisualStyle.panelBorder))
            .shadow(color: .black.opacity(0.36), radius: shadowRadius, y: shadowRadius * 0.42)
    }
}

extension View {
    func workspaceGlassPanel(
        cornerRadius: CGFloat = 16,
        tintOpacity: Double = 0.62,
        shadowRadius: CGFloat = 18
    ) -> some View {
        modifier(
            WorkspaceGlassPanel(
                cornerRadius: cornerRadius,
                tintOpacity: tintOpacity,
                shadowRadius: shadowRadius
            )
        )
    }
}

struct WorkspaceIconButton: View {
    let symbol: String
    let label: String
    var isActive = false
    var size: CGFloat = 34
    var showsHoverLabel = false
    var hoverCalloutPlacement: WorkspaceHoverCalloutPlacement = .trailing
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? WorkspaceVisualStyle.accent : .white.opacity(isHovered ? 0.96 : 0.76))
                .frame(width: size, height: size)
                .background(backgroundColor, in: Circle())
                .overlay(Circle().stroke(borderColor))
                .contentShape(Circle())
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(label)
        .workspaceHoverCallout(
            label,
            isEnabled: showsHoverLabel,
            anchorSize: size,
            placement: hoverCalloutPlacement
        )
    }

    private var backgroundColor: Color {
        if isActive { return WorkspaceVisualStyle.accent.opacity(0.15) }
        return .white.opacity(isHovered ? 0.11 : 0.025)
    }

    private var borderColor: Color {
        if isActive { return WorkspaceVisualStyle.accent.opacity(0.42) }
        return .white.opacity(isHovered ? 0.18 : 0.045)
    }
}

enum WorkspaceHoverCalloutPlacement {
    case trailing
    case below
}

private struct WorkspaceHoverCalloutModifier: ViewModifier {
    let label: String
    let isEnabled: Bool
    let anchorSize: CGFloat
    let placement: WorkspaceHoverCalloutPlacement

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard isEnabled else { return }
                isHovered = hovering
            }
            .overlay(alignment: placement == .trailing ? .leading : .top) {
                if isEnabled, isHovered {
                    callout
                        .allowsHitTesting(false)
                        .transition(
                            .opacity.combined(
                                with: .move(edge: placement == .trailing ? .leading : .top)
                            )
                        )
                        .zIndex(10_000)
                }
            }
            .zIndex(isHovered ? 10_000 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
    }

    @ViewBuilder
    private var callout: some View {
        if placement == .trailing {
            HStack(spacing: 8) {
                Color.clear.frame(width: anchorSize, height: 1)
                calloutLabel
            }
            .fixedSize()
        } else {
            VStack(spacing: 7) {
                Color.clear.frame(width: 1, height: anchorSize)
                calloutLabel
            }
            .fixedSize()
        }
    }

    private var calloutLabel: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.ultraThinMaterial, in: Capsule())
            .background(WorkspaceVisualStyle.panelTint.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.42), radius: 10, y: 4)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

extension View {
    func workspaceHoverCallout(
        _ label: String,
        isEnabled: Bool = true,
        anchorSize: CGFloat = 34,
        placement: WorkspaceHoverCalloutPlacement = .trailing
    ) -> some View {
        modifier(
            WorkspaceHoverCalloutModifier(
                label: label,
                isEnabled: isEnabled,
                anchorSize: anchorSize,
                placement: placement
            )
        )
    }
}

struct WorkspacePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct WorkspaceHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    .white.opacity(isHovered ? 0.075 : 0),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .brightness(configuration.isPressed ? 0.05 : 0)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
        }
    }
}
