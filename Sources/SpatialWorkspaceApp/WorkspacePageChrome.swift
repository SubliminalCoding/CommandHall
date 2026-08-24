import SwiftUI

enum WorkspacePageMode {
    case scrolling
    case immersive
}

enum WorkspacePageMetrics {
    static let maxContentWidth: CGFloat = 1_280
    static let horizontalInset: CGFloat = 28
    static let topInset: CGFloat = 68
    static let bottomInset: CGFloat = 34
    static let contentSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
}

enum WorkspacePageTypography {
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .monospaced)
    static let pageTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let subtitle = Font.system(size: 12)
    static let sectionTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 11)
    static let metadata = Font.system(size: 11, weight: .semibold, design: .monospaced)
}

struct WorkspacePageScaffold<Content: View>: View {
    let theme: WorkspaceTheme
    let mode: WorkspacePageMode

    private let content: Content

    init(
        theme: WorkspaceTheme,
        mode: WorkspacePageMode = .scrolling,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.mode = mode
        self.content = content()
    }

    var body: some View {
        ZStack {
            WorkspaceBackdrop(theme: theme)
            pageContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.01, green: 0.02, blue: 0.05))
        .clipped()
    }

    @ViewBuilder
    private var pageContent: some View {
        switch mode {
        case .scrolling:
            ScrollView {
                VStack(alignment: .leading, spacing: WorkspacePageMetrics.contentSpacing) {
                    content
                }
                .frame(maxWidth: WorkspacePageMetrics.maxContentWidth, alignment: .leading)
                .padding(.horizontal, WorkspacePageMetrics.horizontalInset)
                .padding(.top, WorkspacePageMetrics.topInset)
                .padding(.bottom, WorkspacePageMetrics.bottomInset)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        case .immersive:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct WorkspacePageHeader<Trailing: View>: View {
    let eyebrow: String
    let symbol: String?
    let title: String
    let subtitle: String
    let accent: Color

    private let trailing: Trailing

    init(
        eyebrow: String,
        symbol: String? = nil,
        title: String,
        subtitle: String,
        accent: Color = WorkspaceVisualStyle.cyan,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                titleBlock
                    .layoutPriority(1)
                Spacer(minLength: 24)
                trailing
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                Text(eyebrow.uppercased())
            }
            .font(WorkspacePageTypography.eyebrow)
            .tracking(1.3)
            .foregroundStyle(accent)

            Text(title)
                .font(WorkspacePageTypography.pageTitle)

            Text(subtitle)
                .font(WorkspacePageTypography.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension WorkspacePageHeader where Trailing == EmptyView {
    init(
        eyebrow: String,
        symbol: String? = nil,
        title: String,
        subtitle: String,
        accent: Color = WorkspaceVisualStyle.cyan
    ) {
        self.init(
            eyebrow: eyebrow,
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            accent: accent
        ) {
            EmptyView()
        }
    }
}

struct WorkspaceSectionHeading: View {
    let index: String?
    let title: String
    let detail: String
    var accent = WorkspaceVisualStyle.cyan

    init(index: String? = nil, title: String, detail: String, accent: Color = WorkspaceVisualStyle.cyan) {
        self.index = index
        self.title = title
        self.detail = detail
        self.accent = accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let index {
                Text(index)
                    .font(WorkspacePageTypography.metadata)
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.11), in: Circle())
                    .overlay(Circle().stroke(accent.opacity(0.18)))
                    .accessibilityLabel("Step \(index)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(index == nil ? WorkspacePageTypography.eyebrow : WorkspacePageTypography.sectionTitle)
                    .tracking(index == nil ? 1.1 : 0)
                    .foregroundStyle(index == nil ? accent : Color.primary)
                Text(detail)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

enum WorkspaceStatusTone: Equatable {
    case neutral
    case info
    case working
    case success
    case warning
    case danger
    case live

    var color: Color {
        switch self {
        case .neutral: .white.opacity(0.62)
        case .info: WorkspaceVisualStyle.cyan
        case .working: Color(red: 0.92, green: 0.78, blue: 0.36)
        case .success: Color(red: 0.48, green: 0.86, blue: 0.56)
        case .warning: .orange
        case .danger: Color(red: 0.97, green: 0.42, blue: 0.39)
        case .live: Color(red: 1.0, green: 0.22, blue: 0.24)
        }
    }

    var symbol: String {
        switch self {
        case .neutral: "minus.circle.fill"
        case .info: "info.circle.fill"
        case .working: "bolt.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .live: "dot.radiowaves.left.and.right"
        }
    }

    var label: String {
        switch self {
        case .neutral: "Status"
        case .info: "Information"
        case .working: "Working"
        case .success: "Ready"
        case .warning: "Attention"
        case .danger: "Error"
        case .live: "Live"
        }
    }
}

struct WorkspaceStatusPill: View {
    let text: String
    let detail: String?
    let tone: WorkspaceStatusTone
    let symbol: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        _ text: String,
        detail: String? = nil,
        tone: WorkspaceStatusTone = .neutral,
        symbol: String? = nil
    ) {
        self.text = text
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol ?? tone.symbol)
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .font(WorkspacePageTypography.metadata)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            WorkspaceVisualStyle.panelTint.opacity(reduceTransparency ? 0.98 : 0.72),
            in: Capsule()
        )
        .overlay(Capsule().stroke(tone.color.opacity(0.38)))
        .shadow(color: tone.color.opacity(tone == .neutral ? 0 : 0.16), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [tone.label, text, detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct WorkspaceInlineAlert<Actions: View>: View {
    let title: String
    let message: String
    let tone: WorkspaceStatusTone
    let symbol: String?

    private let actions: Actions

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String,
        message: String,
        tone: WorkspaceStatusTone,
        symbol: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.symbol = symbol
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                alertCopy
                    .layoutPriority(1)
                Spacer(minLength: 12)
                actions
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                alertCopy
                actions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            WorkspaceVisualStyle.panelTint.opacity(reduceTransparency ? 0.98 : 0.64),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tone.color.opacity(0.32))
        }
        .shadow(color: tone.color.opacity(0.10), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var alertCopy: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol ?? tone.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(tone.label.uppercased())
                    .font(WorkspacePageTypography.metadata)
                    .tracking(0.8)
                    .foregroundStyle(tone.color)
                Text(title)
                    .font(WorkspacePageTypography.sectionTitle)
                Text(message)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension WorkspaceInlineAlert where Actions == EmptyView {
    init(
        title: String,
        message: String,
        tone: WorkspaceStatusTone,
        symbol: String? = nil
    ) {
        self.init(title: title, message: message, tone: tone, symbol: symbol) {
            EmptyView()
        }
    }
}

private struct WorkspaceSectionCardModifier: ViewModifier {
    let contentPadding: CGFloat
    let cornerRadius: CGFloat
    let tintOpacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(contentPadding)
            .background(.ultraThinMaterial, in: shape)
            .background(
                WorkspaceVisualStyle.panelTint.opacity(reduceTransparency ? 0.98 : tintOpacity),
                in: shape
            )
            .overlay(shape.stroke(WorkspaceVisualStyle.panelBorder))
            .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
    }
}

private struct WorkspaceTopToolbarModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(4)
            .frame(minHeight: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                WorkspaceVisualStyle.panelTint.opacity(reduceTransparency ? 0.98 : 0.58),
                in: Capsule()
            )
            .overlay(Capsule().stroke(WorkspaceVisualStyle.panelBorder))
            .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
    }
}

private struct WorkspaceSelectableSurfaceModifier: ViewModifier {
    let selected: Bool
    let accent: Color
    let cornerRadius: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(backgroundColor, in: shape)
            .overlay(shape.stroke(borderColor, lineWidth: selected ? 1.2 : 1))
            .shadow(color: selected ? accent.opacity(0.12) : .clear, radius: 10, y: 4)
            .contentShape(shape)
            .onHover { hovering in
                isHovered = isEnabled && hovering
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if selected { return accent.opacity(0.16) }
        if !isEnabled { return .white.opacity(0.018) }
        return .white.opacity(isHovered ? 0.07 : 0.035)
    }

    private var borderColor: Color {
        if selected { return accent.opacity(0.42) }
        if !isEnabled { return .white.opacity(0.04) }
        return .white.opacity(isHovered ? 0.16 : 0.08)
    }
}

private struct WorkspaceFocusSurfaceModifier: ViewModifier {
    let isFocused: Bool
    let accent: Color
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                reduceTransparency ? WorkspaceVisualStyle.panelTint.opacity(0.98) : Color.black.opacity(0.34),
                in: shape
            )
            .overlay(shape.stroke(isFocused ? accent.opacity(0.80) : .white.opacity(0.14), lineWidth: isFocused ? 1.5 : 1))
            .shadow(color: isFocused ? accent.opacity(0.14) : .clear, radius: 10)
            .contentShape(shape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

extension View {
    func workspaceSectionCard(
        padding: CGFloat = 14,
        cornerRadius: CGFloat = 14,
        tintOpacity: Double = 0.50
    ) -> some View {
        modifier(
            WorkspaceSectionCardModifier(
                contentPadding: padding,
                cornerRadius: cornerRadius,
                tintOpacity: tintOpacity
            )
        )
    }

    func workspaceTopToolbar() -> some View {
        modifier(WorkspaceTopToolbarModifier())
    }

    func workspaceSelectableSurface(
        selected: Bool,
        accent: Color = WorkspaceVisualStyle.cyan,
        cornerRadius: CGFloat = 10
    ) -> some View {
        modifier(
            WorkspaceSelectableSurfaceModifier(
                selected: selected,
                accent: accent,
                cornerRadius: cornerRadius
            )
        )
    }

    func workspaceFocusSurface(
        isFocused: Bool,
        accent: Color = WorkspaceVisualStyle.cyan,
        cornerRadius: CGFloat = 10
    ) -> some View {
        modifier(
            WorkspaceFocusSurfaceModifier(
                isFocused: isFocused,
                accent: accent,
                cornerRadius: cornerRadius
            )
        )
    }
}
