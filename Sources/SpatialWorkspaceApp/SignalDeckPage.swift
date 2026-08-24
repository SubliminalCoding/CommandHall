import SwiftUI

struct SignalDeckPage: View {
    @ObservedObject var controller: SignalDeckController
    let theme: WorkspaceTheme

    var body: some View {
        WorkspacePageScaffold(theme: theme) {
            pageHeader
            truthBanner
            actionFeedback
            pendingApprovalSection
            profileSection
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: WorkspacePageMetrics.sectionSpacing) {
                    sourceSection.frame(maxWidth: .infinity)
                    busSection.frame(maxWidth: .infinity)
                }
                VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                    sourceSection
                    busSection
                }
            }
            checkSection
            changeRecordSection
        }
        .accessibilityLabel("Signal Deck audio routing page")
    }

    private var pageHeader: some View {
        WorkspacePageHeader(
            eyebrow: "Audio Routing",
            symbol: "waveform.path.ecg.rectangle",
            title: "Signal Deck",
            subtitle: "Configure who you hear, what OBS receives, and which sources stay private.",
            accent: theme.accent
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 7) {
                    WorkspaceStatusPill(
                        controller.streamState.label,
                        tone: controller.streamState == .live ? .live : .neutral,
                        symbol: controller.streamState == .live ? "dot.radiowaves.left.and.right" : "dot.circle"
                    )
                    WorkspaceStatusPill(
                        controller.connectionState.label,
                        tone: connectionTone,
                        symbol: connectionSymbol
                    )
                }
                pageActions
                Text(controller.detail)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 430, alignment: .trailing)
            }
        }
    }

    private var truthBanner: some View {
        WorkspaceInlineAlert(
            title: truthTitle,
            message: truthDetail,
            tone: truthTone,
            symbol: truthSymbol
        ) {
            if let revision = controller.snapshot?.revision {
                Text("REV \(revision)")
                    .font(WorkspacePageTypography.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(.white.opacity(0.05), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.10)))
            }
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let error = controller.actionError {
            WorkspaceInlineAlert(
                title: "The routing change was not applied",
                message: error,
                tone: .danger,
                symbol: "exclamationmark.triangle.fill"
            )
        } else if let message = controller.actionMessage {
            WorkspaceInlineAlert(
                title: "Signal Deck update",
                message: message,
                tone: .info,
                symbol: "info.circle.fill"
            )
        }
    }

    @ViewBuilder
    private var pendingApprovalSection: some View {
        if !controller.pendingApprovals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading(
                    "APPROVALS",
                    detail: "These changes can add sound to an external mix while stream status is live or unavailable. Nothing below has been applied."
                )
                ForEach(controller.pendingApprovals) { plan in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.summary)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text("\(plan.direction.label.uppercased()) · REV \(plan.expectedRevision)")
                                    .font(WorkspacePageTypography.metadata)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(plan.requester)
                                .font(WorkspacePageTypography.metadata)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(plan.preview) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.resource)
                                    .font(WorkspacePageTypography.body.weight(.semibold))
                                    .frame(width: 118, alignment: .leading)
                                Text(item.before)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.orange)
                                Text(item.after)
                            }
                            .font(WorkspacePageTypography.metadata)
                        }
                        HStack {
                            Label("Expires shortly if the router changes or the plan is not used", systemImage: "timer")
                                .font(WorkspacePageTypography.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Dismiss") { controller.rejectPlan(plan.id) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Approve & Configure") {
                                Task { await controller.approvePlan(plan.id) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.orange)
                            .disabled(controller.executingPlanID != nil)
                        }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.orange.opacity(0.28)))
                }
            }
            .workspaceSectionCard()
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                "PROFILES",
                detail: "A profile changes the durable logical graph atomically. Configured does not mean applied to live audio."
            )
            if let profiles = controller.profiles?.profiles, !profiles.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                    ForEach(profiles) { profile in
                        profileCard(profile)
                    }
                }
            } else {
                unavailableRow("Profiles will appear after an authenticated full snapshot is received.")
            }
            if controller.hasCatalogDrift, let savedID = controller.snapshot?.configuredProfile?.id {
                Label(
                    "The saved \(savedID) graph does not match the current catalog definition. Configure a profile to update it explicitly.",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.orange)
            }
        }
        .workspaceSectionCard()
    }

    private func profileCard(_ profile: SignalDeckProfile) -> some View {
        let configured = controller.configuredProfileID == profile.id
        let active = controller.snapshot?.activeProfile?.id == profile.id
        let applying = controller.applyingProfileID == profile.id
        let pending = controller.pendingProfileID == profile.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(profile.id.uppercased())
                        .font(WorkspacePageTypography.metadata)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    profileBadge("ACTIVE", color: .green)
                } else if configured {
                    profileBadge("CONFIGURED", color: theme.accent)
                } else if pending {
                    profileBadge("RETRY SAFE", color: .orange)
                }
            }
            Text(profile.description)
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(profile.routes.count) sources · \(profile.buses.count) buses")
                    .font(WorkspacePageTypography.metadata)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(applying ? "Configuring…" : (pending ? "Retry" : (configured ? "Configured" : "Configure"))) {
                    Task { await controller.applyProfile(profile.id) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(configured ? .gray : theme.accent)
                .disabled(!controller.canApplyProfile(profile.id))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(configured ? theme.accent.opacity(0.08) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(configured ? theme.accent.opacity(0.35) : .white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("SOURCES", detail: "Current logical destinations. Unavailable sources have not been bound to a macOS process yet.")
            if let sources = controller.snapshot?.sources, !sources.isEmpty {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(source.displayName, systemImage: sourceSymbol(source.id))
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            stateLabel(source.muted ? "MUTED" : (source.available ? "READY" : "LOGICAL"), color: source.muted ? .orange : (source.available ? .green : .secondary))
                        }
                        if source.targetBusIds.isEmpty {
                            Text("No destination buses")
                                .font(WorkspacePageTypography.metadata)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(source.targetBusIds, id: \.self) { busID in
                                        Text(busName(busID))
                                            .font(WorkspacePageTypography.metadata)
                                            .padding(.horizontal, 7)
                                            .frame(height: 22)
                                            .background(theme.accent.opacity(0.08), in: Capsule())
                                            .overlay(Capsule().stroke(theme.accent.opacity(0.18)))
                                    }
                                }
                            }
                        }
                        if let processingBusIDs = source.processingBusIds, !processingBusIDs.isEmpty {
                            Text("PROCESSING · \(processingBusIDs.map(busName).joined(separator: " → "))")
                                .font(WorkspacePageTypography.metadata)
                                .foregroundStyle(theme.accent.opacity(0.82))
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            semanticButton(
                                "Private",
                                symbol: "headphones",
                                action: .listenPrivately(sourceID: source.id)
                            )
                            if source.targetBusIds.contains("stream-mix") {
                                semanticButton(
                                    "Exclude",
                                    symbol: "rectangle.slash",
                                    action: .excludeFromStream(sourceID: source.id)
                                )
                            } else {
                                semanticButton(
                                    "Include",
                                    symbol: "dot.radiowaves.left.and.right",
                                    action: .includeInStream(sourceID: source.id),
                                    tint: .orange
                                )
                            }
                            semanticButton(
                                "Mute",
                                symbol: "speaker.slash.fill",
                                action: .muteSource(sourceID: source.id)
                            )
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            } else {
                unavailableRow("No authoritative source snapshot is available.")
            }
        }
        .workspaceSectionCard()
    }

    private var busSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("BUSES", detail: "Named destinations and their current logical controls.")
            if let buses = controller.snapshot?.buses, !buses.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(buses) { bus in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(bus.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Circle()
                                    .fill(bus.clipping ? Color.red : (bus.available ? Color.green : Color.orange))
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.07))
                                    Capsule()
                                        .fill(bus.clipping ? Color.red : theme.accent)
                                        .frame(width: meterWidth(bus, availableWidth: proxy.size.width))
                                }
                            }
                            .frame(height: 4)
                            HStack {
                                Text(bus.muted ? "MUTED" : "GAIN \(bus.gain, specifier: "%.2f")")
                                Spacer()
                                if bus.clipping {
                                    Label("CLIP", systemImage: "waveform.badge.exclamationmark")
                                        .foregroundStyle(.red)
                                } else {
                                    Text(bus.available ? "READY" : "NOT MATERIALIZED")
                                }
                            }
                            .font(WorkspacePageTypography.metadata)
                            .foregroundStyle(.secondary)
                            Button(bus.muted ? "Unmute configuration" : "Mute configuration") {
                                Task {
                                    await controller.requestFromUI(.setBusMuted(busID: bus.id, muted: !bus.muted))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(bus.muted && (bus.role == "stream" || bus.role == "chat" || bus.role == "record") ? .orange : theme.accent)
                            .disabled(!controller.canPlan(.setBusMuted(busID: bus.id, muted: !bus.muted)))
                            .accessibilityHint("Changes the durable \(bus.displayName) bus configuration")
                        }
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .help(bus.available ? bus.displayName : bus.availabilityReason)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(
                            "\(bus.displayName), \(bus.muted ? "muted" : "gain \(bus.gain)"), \(bus.available ? "available" : "not materialized")\(bus.clipping ? ", clipping" : "")"
                        )
                    }
                }
            } else {
                unavailableRow("No authoritative bus snapshot is available.")
            }
        }
        .workspaceSectionCard()
    }

    private var checkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("READINESS", detail: "These are SignalDeck's own bounded checks, not inferred status.")
            if let checks = controller.snapshot?.checks, !checks.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 9)], spacing: 9) {
                    ForEach(checks) { check in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: checkSymbol(check.status))
                                .foregroundStyle(checkTone(check.status).color)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 7) {
                                    Text(check.id.replacingOccurrences(of: "-", with: " ").uppercased())
                                        .font(WorkspacePageTypography.metadata)
                                    Text(checkLabel(check.status))
                                        .font(WorkspacePageTypography.metadata)
                                        .foregroundStyle(checkTone(check.status).color)
                                }
                                Text(check.message)
                                    .font(WorkspacePageTypography.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            } else {
                unavailableRow("Readiness checks are waiting for SignalDeck.")
            }
        }
        .workspaceSectionCard()
    }

    private var changeRecordSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                receiptHistory.frame(maxWidth: .infinity)
                proposalAudit.frame(maxWidth: .infinity)
            }
            VStack(spacing: 14) {
                receiptHistory
                proposalAudit
            }
        }
    }

    private var receiptHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                "RECEIPTS",
                detail: "Receipts prove accepted configuration mutations. They do not prove that audible routing changed."
            )
            if controller.receiptHistory.isEmpty {
                unavailableRow("No SignalDeck mutations have been accepted during this app session.")
            } else {
                ForEach(Array(controller.receiptHistory.prefix(8)), id: \.operationId) { receipt in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: receipt.appliedToEngine ? "waveform.badge.checkmark" : "doc.badge.gearshape")
                            .foregroundStyle(receipt.appliedToEngine ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(receipt.operation.uppercased())
                                    .font(WorkspacePageTypography.metadata)
                                Spacer()
                                Text("REV \(receipt.beforeRevision) → \(receipt.afterRevision)")
                                    .font(WorkspacePageTypography.metadata)
                                    .foregroundStyle(.secondary)
                            }
                            Text(receipt.resourceId ?? receipt.profileId ?? "all routes")
                                .font(WorkspacePageTypography.body.weight(.semibold))
                            Text(receipt.appliedToEngine ? "APPLIED · CONTENT NOT ATTESTED" : "CONFIGURED · NOT APPLIED TO ENGINE")
                                .font(WorkspacePageTypography.metadata)
                                .foregroundStyle(receipt.appliedToEngine ? Color.green : Color.orange)
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .workspaceSectionCard()
    }

    private var proposalAudit: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                "CHANGE LOG",
                detail: "Local proposal and approval decisions. Credentials and raw control payloads are never shown."
            )
            if controller.auditTrail.isEmpty {
                unavailableRow("Plans, approvals, rejections, and configured receipts will appear here.")
            } else {
                ForEach(Array(controller.auditTrail.prefix(10))) { entry in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(auditColor(entry.kind))
                            .frame(width: 7, height: 7)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.kind.rawValue.uppercased())
                                    .font(WorkspacePageTypography.metadata)
                                    .foregroundStyle(auditColor(entry.kind))
                                Text(entry.requester)
                                    .font(WorkspacePageTypography.metadata)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.summary)
                                .font(WorkspacePageTypography.body.weight(.semibold))
                            Text(entry.detail)
                                .font(WorkspacePageTypography.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(9)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .workspaceSectionCard()
    }

    private var pageActions: some View {
        HStack(spacing: 6) {
            Button {
                Task { await controller.requestFromUI(.panicMute) }
            } label: {
                Label("Mute all", systemImage: "speaker.slash.fill")
                    .font(WorkspacePageTypography.metadata)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(.red.opacity(0.13), in: Capsule())
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .foregroundStyle(.red)
            .disabled(!controller.canPlan(.panicMute))
            .help("Close the Stream safety gate and persist every route and bus muted")
            WorkspaceIconButton(
                symbol: "arrow.clockwise",
                label: "Reconnect to Signal Deck",
                size: 30,
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.reconnect
            )
            .help("Reload owner-only discovery and request a full snapshot")
        }
        .workspaceTopToolbar()
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        WorkspaceSectionHeading(title: title, detail: detail, accent: theme.accent)
    }

    private func unavailableRow(_ message: String) -> some View {
        Label(message, systemImage: "waveform.badge.exclamationmark")
            .font(WorkspacePageTypography.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func profileBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(WorkspacePageTypography.metadata)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25)))
    }

    private func stateLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(WorkspacePageTypography.metadata)
            .foregroundStyle(color)
    }

    private func semanticButton(
        _ title: String,
        symbol: String,
        action: SignalDeckSemanticAction,
        tint: Color? = nil
    ) -> some View {
        Button {
            Task { await controller.requestFromUI(action) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint ?? theme.accent)
        .disabled(!controller.canPlan(action))
        .frame(maxWidth: .infinity)
    }

    private func auditColor(_ kind: SignalDeckAuditKind) -> Color {
        switch kind {
        case .configured: .green
        case .failed, .stale, .expired: .red
        case .approvalRequired, .approved: .orange
        case .rejected: .secondary
        case .planned, .automatic: theme.accent
        }
    }

    private func busName(_ id: String) -> String {
        controller.snapshot?.buses.first(where: { $0.id == id })?.displayName ?? id
    }

    private func sourceSymbol(_ id: String) -> String {
        switch id {
        case "microphone": "mic.fill"
        case "discord": "bubble.left.and.bubble.right.fill"
        case "browser": "globe"
        case "music": "music.note"
        case "jarvis": "waveform.circle.fill"
        default: "desktopcomputer"
        }
    }

    private func meterWidth(_ bus: SignalDeckBus, availableWidth: CGFloat) -> CGFloat {
        guard let peak = bus.peakDbfs else { return 0 }
        let normalized = min(max((peak + 60) / 60, 0), 1)
        return availableWidth * normalized
    }

    private var connectionTone: WorkspaceStatusTone {
        switch controller.statusColorName {
        case "green": .success
        case "orange": .warning
        case "yellow": .working
        default: .danger
        }
    }

    private var connectionSymbol: String {
        if controller.connected && controller.isAuthoritative { return "checkmark.circle.fill" }
        if controller.connectionState == .connecting || controller.connectionState == .reconnecting {
            return "arrow.triangle.2.circlepath"
        }
        return "exclamationmark.triangle.fill"
    }

    private var truthTitle: String {
        if !controller.isAuthoritative { return "Showing last-known routing state" }
        if !controller.configurationAvailable { return "Routing configuration needs recovery" }
        switch controller.routingTruth {
        case .unavailable: return "Routing state is unavailable"
        case .configuredOnly: return "Configuration only: live audio is not rerouted"
        case .appliedUnverified: return "Audio graph reports applied, but verification is incomplete"
        case .engineVerified: return "SignalDeck verifies engine application"
        }
    }

    private var truthDetail: String {
        if !controller.isAuthoritative {
            return "Controls are disabled until Signal Deck reconnects and confirms a fresh revision. Source, bus, profile, and readiness values below may be stale."
        }
        if !controller.configurationAvailable {
            return "SignalDeck preserved the original state file and disabled mutations. Repair it in SignalDeck before changing profiles."
        }
        switch controller.routingTruth {
        case .unavailable:
            return "Reconnect and wait for an authoritative snapshot before planning a change."
        case .configuredOnly:
            return "SignalDeck preserves revisions and receipts, but the current backend reports configuration-only. No control here claims that OBS or your headphones changed."
        case .appliedUnverified:
            return "The graph reports application, but its engine health checks have not verified the revision. Monitor audio before relying on it."
        case .engineVerified:
            return "The engine and audio-graph check agree on application. This verifies topology, not that the intended program content is audible."
        }
    }

    private var truthTone: WorkspaceStatusTone {
        if !controller.isAuthoritative { return .warning }
        return switch controller.routingTruth {
        case .engineVerified: .success
        case .appliedUnverified: .working
        case .configuredOnly: .warning
        case .unavailable: .danger
        }
    }

    private var truthSymbol: String {
        if !controller.isAuthoritative { return "clock.badge.exclamationmark" }
        return switch controller.routingTruth {
        case .engineVerified: "waveform.badge.checkmark"
        case .appliedUnverified: "waveform.badge.exclamationmark"
        case .configuredOnly: "point.3.connected.trianglepath.dotted"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private func checkTone(_ status: String) -> WorkspaceStatusTone {
        switch status {
        case "pass": .success
        case "warn": .warning
        default: .danger
        }
    }

    private func checkSymbol(_ status: String) -> String {
        switch status {
        case "pass": "checkmark.circle.fill"
        case "warn": "exclamationmark.triangle.fill"
        default: "xmark.octagon.fill"
        }
    }

    private func checkLabel(_ status: String) -> String {
        switch status {
        case "pass": "PASS"
        case "warn": "WARNING"
        default: "FAIL"
        }
    }
}
