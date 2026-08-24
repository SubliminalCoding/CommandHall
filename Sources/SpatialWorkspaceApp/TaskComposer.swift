import AppKit
import SwiftUI

struct TaskComposer: View {
    @Binding var text: String
    let prompt: String
    let targetLabel: String
    let statusMessage: String?
    let intentPreview: WorkspaceCommandPlan?
    let disabled: Bool
    let focus: FocusState<Bool>.Binding
    let onSubmit: (String) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sendHovered = false
    @State private var returnMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 9) {
                TextField(prompt, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1 ... 6)
                    .focused(focus)
                    .disabled(disabled)
                    // Return-to-send is handled by an AppKit key monitor rather
                    // than `.onKeyPress`, which fires unreliably on a multiline
                    // (`axis: .vertical`) TextField — the field editor consumes
                    // Return first, so submit never ran and the keystroke fell
                    // through to select-the-field. The monitor intercepts Return
                    // before the field editor while this composer is focused.
                    .onChange(of: focus.wrappedValue) { _, focused in
                        if focused { installReturnMonitor() } else { removeReturnMonitor() }
                    }
                    .onDisappear { removeReturnMonitor() }
                    .accessibilityLabel(prompt)
                    .accessibilityHint("Press Return to send. Press Shift and Return for a new line.")

                Button(action: submit) {
                    Image(systemName: disabled ? "hourglass" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSubmit ? Color.black : .secondary)
                        .frame(width: 34, height: 34)
                        .background(canSubmit ? WorkspaceVisualStyle.accent : .white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(canSubmit && sendHovered ? .white.opacity(0.66) : .clear, lineWidth: 1))
                        .shadow(color: canSubmit ? WorkspaceVisualStyle.accent.opacity(sendHovered ? 0.45 : 0.18) : .clear, radius: 10)
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .disabled(!canSubmit)
                .onHover { sendHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: sendHovered)
                .accessibilityLabel("Send to \(targetLabel)")
                .accessibilityHint("The draft clears after the command is accepted.")
            }

            HStack(spacing: 7) {
                Label(targetLabel, systemImage: "scope")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(.white.opacity(0.07), in: Capsule())
                if let intentPreview {
                    HStack(spacing: 5) {
                        Image(systemName: intentPreview.symbol)
                        Text(intentPreview.detail)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(intentColor(for: intentPreview))
                    .help(intentPreview.detail)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Command intent: \(intentPreview.detail)")
                } else if let statusMessage, !statusMessage.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor(for: statusMessage))
                            .frame(width: 5, height: 5)
                        Text(statusMessage)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(intentPreview?.requiresConfirmation == true
                    ? "Return opens review"
                    : "Return sends  ·  Shift-Return adds a line")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.28))
    }

    private var canSubmit: Bool {
        !disabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        _ = TaskComposerSubmission.submit(text: &text, disabled: disabled, onSubmit: onSubmit)
    }

    /// Catch Return before the field editor turns it into a newline. Only the
    /// focused composer consumes it; Shift-Return and the numeric-keypad path
    /// fall through so a deliberate line break still works.
    private func installReturnMonitor() {
        guard returnMonitor == nil else { return }
        returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = event.keyCode == 36 || event.keyCode == 76 // Return, keypad Enter
            guard isReturn,
                  !event.modifierFlags.contains(.shift),
                  focus.wrappedValue,
                  !disabled else { return event }
            submit()
            return nil // consume so no newline is inserted
        }
    }

    private func removeReturnMonitor() {
        if let returnMonitor {
            NSEvent.removeMonitor(returnMonitor)
            self.returnMonitor = nil
        }
    }

    private func statusColor(for message: String) -> Color {
        let value = message.lowercased()
        if value.contains("no matching") || value.contains("failed") || value.contains("error") { return .orange }
        if value.contains("sent") || value.contains("created") || value.contains("complete") { return .green }
        return WorkspaceVisualStyle.cyan
    }

    private func intentColor(for plan: WorkspaceCommandPlan) -> Color {
        if !plan.isExecutable { return .orange }
        if plan.requiresConfirmation { return WorkspaceVisualStyle.accent }
        return WorkspaceVisualStyle.cyan
    }
}

struct CommandPlanConfirmationView: View {
    let plan: WorkspaceCommandPlan
    let onRun: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WorkspaceVisualStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(WorkspaceVisualStyle.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review planned changes")
                        .font(.system(size: 12, weight: .semibold))
                    Text(plan.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.06), in: Capsule())
                    .keyboardShortcut(.cancelAction)

                Button(action: onRun) {
                    Label("Run", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(WorkspaceVisualStyle.accent, in: Capsule())
                        .shadow(
                            color: WorkspaceVisualStyle.accent.opacity(runHovered ? 0.42 : 0.18),
                            radius: 9
                        )
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .keyboardShortcut(.defaultAction)
                .onHover { runHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: runHovered)
            }

            Label(plan.detail, systemImage: "list.bullet")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(plan.detail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review command. \(plan.detail)")
    }
}

enum TaskComposerSubmission {
    @discardableResult
    static func submit(text: inout String, disabled: Bool, onSubmit: (String) -> Bool) -> Bool {
        let originalText = text
        let request = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !disabled else { return false }

        text = ""
        guard onSubmit(request) else {
            text = originalText
            return false
        }
        return true
    }
}
