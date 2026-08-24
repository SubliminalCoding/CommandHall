import SwiftUI

private enum WorkspaceLibrarySection: String, CaseIterable, Identifiable {
    case memory = "Memory"
    case timeline = "Timeline"

    var id: String { rawValue }
}

private struct WorkspaceMemoryDraft: Identifiable {
    let id = UUID()
    var entryID: UUID?
    var kind: WorkspaceMemoryKind = .standingInstruction
    var title = ""
    var detail = ""
    var alwaysInclude = false
}

struct WorkspaceMemoryTimelineView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    @State private var section = WorkspaceLibrarySection.memory
    @State private var searchText = ""
    @State private var draft: WorkspaceMemoryDraft?

    private var searchResults: [WorkspaceSearchResult] {
        store.searchWorkspace(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsView
            } else if section == .memory {
                memoryView
            } else {
                timelineView
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(WorkspaceVisualStyle.panelTint.opacity(0.96))
        .sheet(item: $draft) { draft in
            WorkspaceMemoryEditor(
                draft: draft,
                onSave: save,
                onCancel: { self.draft = nil }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workspace library")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(store.activeWorkspace.name) · local context and activity")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    draft = WorkspaceMemoryDraft()
                } label: {
                    Label("Add memory", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                Picker("Section", selection: $section) {
                    ForEach(WorkspaceLibrarySection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                TextField("Search runs, evidence, artifacts, sessions, and memory", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var memoryView: some View {
        if store.workspaceMemory.isEmpty {
            ContentUnavailableView {
                Label("No workspace memory", systemImage: "brain.head.profile")
            } description: {
                Text("Add goals, decisions, constraints, and standing instructions. Relevant entries can be supplied to agent runs with visible provenance.")
            } actions: {
                Button("Add memory") { draft = WorkspaceMemoryDraft() }
            }
        } else {
            List(store.workspaceMemory) { entry in
                memoryRow(entry)
            }
            .listStyle(.inset)
        }
    }

    private func memoryRow(_ entry: WorkspaceMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.alwaysInclude ? Color.orange : Color.accentColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(entry.title).font(.system(size: 13, weight: .semibold))
                    Text(entry.kind.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    if entry.alwaysInclude {
                        Text("ALWAYS INCLUDE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(entry.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(3)
                Text("Source: \(entry.sourceLabel) · Updated \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit") { edit(entry) }
                Button("Delete", role: .destructive) { store.removeMemoryEntry(entry.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 24)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var timelineView: some View {
        let items = store.workspaceTimeline()
        if items.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath")
        } else {
            List(items) { item in
                Button { open(item) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.kind.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(searchResults) { result in
                Button { open(result) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(result.kind.label.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(result.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(result.date == .distantPast ? "" : result.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private func edit(_ entry: WorkspaceMemoryEntry) {
        draft = WorkspaceMemoryDraft(
            entryID: entry.id,
            kind: entry.kind,
            title: entry.title,
            detail: entry.detail,
            alwaysInclude: entry.alwaysInclude
        )
    }

    private func save(_ value: WorkspaceMemoryDraft) {
        if let entryID = value.entryID {
            store.updateMemoryEntry(
                entryID,
                kind: value.kind,
                title: value.title,
                detail: value.detail,
                alwaysInclude: value.alwaysInclude
            )
        } else {
            store.addMemoryEntry(
                kind: value.kind,
                title: value.title,
                detail: value.detail,
                alwaysInclude: value.alwaysInclude
            )
        }
        draft = nil
    }

    private func open(_ item: WorkspaceTimelineItem) {
        if let runID = item.runID { store.beginReview(runID) }
        else if let nodeID = item.nodeID { store.select(nodeID) }
    }

    private func open(_ result: WorkspaceSearchResult) {
        if let memoryID = result.memoryID,
           let entry = store.workspaceMemory.first(where: { $0.id == memoryID }) {
            edit(entry)
        } else if let artifact = result.artifact, let runID = result.runID {
            store.openArtifact(artifact, from: runID)
            isPresented = false
        } else if let runID = result.runID {
            store.beginReview(runID)
            isPresented = false
        } else if let nodeID = result.nodeID {
            store.select(nodeID)
            isPresented = false
        }
    }
}

private struct WorkspaceMemoryEditor: View {
    @State private var value: WorkspaceMemoryDraft
    let onSave: (WorkspaceMemoryDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: WorkspaceMemoryDraft,
        onSave: @escaping (WorkspaceMemoryDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _value = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(value.entryID == nil ? "Add workspace memory" : "Edit workspace memory")
                .font(.system(size: 19, weight: .bold))
            Picker("Type", selection: $value.kind) {
                ForEach(WorkspaceMemoryKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            TextField("Short title", text: $value.title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $value.detail)
                .font(.system(size: 13))
                .frame(minHeight: 150)
                .padding(8)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            Toggle("Always include in agent tasks for this workspace", isOn: $value.alwaysInclude)
            Text("Unpinned entries are selected only when their terms match the task. Every included entry remains visible on the run.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(value) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || value.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
