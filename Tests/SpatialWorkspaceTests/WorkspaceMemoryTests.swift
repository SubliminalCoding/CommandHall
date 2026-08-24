import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspaceMemoryTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-memory-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    func testRetrievalIncludesPinnedAndRelevantEntriesButNotUnrelatedMemory() throws {
        let entries = [
            WorkspaceMemoryEntry(
                kind: .standingInstruction,
                title: "Run tests",
                detail: "Always run Swift tests before completion",
                sourceLabel: "Matt",
                alwaysInclude: true
            ),
            WorkspaceMemoryEntry(
                kind: .convention,
                title: "Terminal layout",
                detail: "Keep terminal controls centered",
                sourceLabel: "UI review"
            ),
            WorkspaceMemoryEntry(
                kind: .reference,
                title: "Music library",
                detail: "Local songs are under Music",
                sourceLabel: "Project note"
            ),
        ]

        let result = WorkspaceMemoryRetrieval.relevantEntries(
            for: "Improve the terminal controls and verify the result",
            in: entries
        )

        XCTAssertEqual(Set(result.map(\.title)), Set(["Run tests", "Terminal layout"]))
        XCTAssertFalse(result.contains(where: { $0.title == "Music library" }))
    }

    func testAgentRunFreezesIncludedMemoryWithVisibleSource() throws {
        let url = temporaryURL()
        let store = WorkspaceStore(persistenceURL: url, runtimeEnabled: false)
        let entryID = try XCTUnwrap(store.addMemoryEntry(
            kind: .constraint,
            title: "Terminal placement",
            detail: "Keep the expanded terminal centered on screen",
            alwaysInclude: false,
            sourceLabel: "Matt · workspace decision"
        ))
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .codex }))

        XCTAssertTrue(store.sendTask("Polish the terminal placement", to: agent.id))
        let run = try XCTUnwrap(store.latestRun(for: agent.id))
        let included = store.includedMemory(for: run)

        XCTAssertEqual(run.includedMemoryEntryIDs, [entryID])
        XCTAssertEqual(included.first?.sourceLabel, "Matt · workspace decision")
        XCTAssertTrue(store.activeWorkspace.nodes.first(where: { $0.id == agent.id })?.activityLog?.contains("Workspace memory") == true)
        let envelope = WorkspaceStore.runtimeGoal(for: run.request, target: agent, memoryEntries: included)
        XCTAssertTrue(envelope.contains("source: Matt · workspace decision"))
        XCTAssertTrue(envelope.contains(entryID.uuidString.lowercased()))

        store.updateMemoryEntry(
            entryID,
            kind: .constraint,
            title: "Terminal placement",
            detail: "This newer wording must not rewrite the completed run",
            alwaysInclude: false
        )
        store.removeMemoryEntry(entryID)
        let frozenRun = try XCTUnwrap(store.latestRun(for: agent.id))
        XCTAssertEqual(store.includedMemory(for: frozenRun).first?.detail, "Keep the expanded terminal centered on screen")

        let reloaded = WorkspaceStore(persistenceURL: url)
        let persistedRun = try XCTUnwrap(reloaded.latestRun(for: agent.id))
        XCTAssertEqual(reloaded.includedMemory(for: persistedRun).first?.sourceLabel, "Matt · workspace decision")
    }

    func testMemoryAndSearchNeverLeakAcrossWorkspaces() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        store.addMemoryEntry(
            kind: .decision,
            title: "Night Shift decision",
            detail: "Use the nocturne terminal layout"
        )
        XCTAssertEqual(store.searchWorkspace("nocturne terminal").map(\.kind), [.memory])

        store.switchWorkspace(named: "Test App")

        XCTAssertTrue(store.workspaceMemory.isEmpty)
        XCTAssertTrue(store.searchWorkspace("nocturne terminal").isEmpty)
        XCTAssertTrue(store.relevantMemory(for: "Update the nocturne terminal").isEmpty)
    }

    func testTimelineAndSearchUnifyCommandsRunsAndMemory() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        store.addMemoryEntry(
            kind: .goal,
            title: "Polished terminal",
            detail: "The expanded terminal should feel centered"
        )
        XCTAssertTrue(store.execute("Ask Marshall to inspect the persistence layer"))

        let timeline = store.workspaceTimeline()
        XCTAssertTrue(timeline.contains(where: { $0.kind == .memory && $0.title == "Polished terminal" }))
        XCTAssertTrue(timeline.contains(where: { $0.kind == .command && $0.detail.contains("Ask Marshall") }))
        XCTAssertTrue(timeline.contains(where: { $0.kind == .task && $0.detail == "inspect the persistence layer" }))
        XCTAssertTrue(store.searchWorkspace("persistence layer").contains(where: { $0.kind == .run }))
        XCTAssertTrue(store.searchWorkspace("centered").contains(where: { $0.kind == .memory }))
    }

    func testMemoryPersistsWithProvenanceAndPinnedState() throws {
        let url = temporaryURL()
        let first = WorkspaceStore(persistenceURL: url)
        let entryID = try XCTUnwrap(first.addMemoryEntry(
            kind: .standingInstruction,
            title: "Verification",
            detail: "Run the acceptance suite",
            alwaysInclude: true,
            sourceLabel: "Release checklist"
        ))

        let reloaded = WorkspaceStore(persistenceURL: url)
        let entry = try XCTUnwrap(reloaded.workspaceMemory.first(where: { $0.id == entryID }))

        XCTAssertEqual(entry.kind, .standingInstruction)
        XCTAssertEqual(entry.sourceLabel, "Release checklist")
        XCTAssertTrue(entry.alwaysInclude)
    }
}
