import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspacePersistenceTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("workspaces.json")
    }

    func testCorruptPrimaryRecoversBackupAndArchivesBadBytes() throws {
        let url = try temporaryURL()
        var first = WorkspaceStore.defaultState()
        first.workspaces[0].name = "Recover Me"
        try WorkspacePersistence.save(first, to: url)

        var second = first
        second.workspaces[0].name = "Newest"
        try WorkspacePersistence.save(second, to: url)
        try Data("{broken".utf8).write(to: url, options: .atomic)

        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)

        XCTAssertEqual(loaded.source, .backup)
        XCTAssertEqual(loaded.state.workspaces[0].name, "Recover Me")
        let archives = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("workspaces.corrupt-") }
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: archives[0]), Data("{broken".utf8))
    }

    func testOlderSchemaIsMigratedWithoutLosingWorkspaceData() throws {
        let url = try temporaryURL()
        var old = WorkspaceStore.defaultState()
        old.schemaVersion = 2
        let encoder = JSONEncoder()
        try encoder.encode(old).write(to: url, options: .atomic)

        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)

        XCTAssertEqual(loaded.source, .migrated(2))
        XCTAssertEqual(loaded.state.schemaVersion, WorkspacePersistence.currentSchemaVersion)
        XCTAssertEqual(loaded.state.workspaces.map(\.name), old.workspaces.map(\.name))
        XCTAssertEqual(loaded.state.workspaces.flatMap(\.nodes).map(\.id), old.workspaces.flatMap(\.nodes).map(\.id))
    }

    func testJarvisConversationIdentityAndHistoryPersist() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let jarvisID = store.createSession(provider: .jarvis, name: "Jarvis", purpose: "Strategic advisor")
        XCTAssertTrue(store.sendTask("Give me the blunt version", to: jarvisID))

        let reloaded = WorkspaceStore(persistenceURL: url)
        let jarvis = try XCTUnwrap(reloaded.activeWorkspace.nodes.first(where: { $0.id == jarvisID }))

        XCTAssertEqual(jarvis.resolvedProvider, .jarvis)
        XCTAssertEqual(jarvis.chatHistory?.map(\.role), [.user])
        XCTAssertEqual(jarvis.chatHistory?.first?.content, "Give me the blunt version")
    }

    func testAgentTerminalViewAndActivityPersist() throws {
        let url = try temporaryURL()
        var state = WorkspaceStore.defaultState()
        let agentIndex = try XCTUnwrap(state.workspaces[0].nodes.firstIndex(where: { $0.isCodingAgent }))
        state.workspaces[0].nodes[agentIndex].agentDisplayMode = .terminal
        state.workspaces[0].nodes[agentIndex].activityLog = "$ swift test\n129 tests passed\n[exit 0]\n"

        try WorkspacePersistence.save(state, to: url)
        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)
        let agent = loaded.state.workspaces[0].nodes[agentIndex]

        XCTAssertEqual(agent.resolvedAgentDisplayMode, .terminal)
        XCTAssertEqual(agent.activityLog, "$ swift test\n129 tests passed\n[exit 0]\n")
    }

    func testPerSessionWorkingFolderChoicePersists() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let unattachedID = store.createSession(
            provider: .shell,
            name: "Scratch",
            purpose: "",
            workingFolderMode: .unattached
        )
        let customID = store.createSession(
            provider: .codex,
            name: "Project Agent",
            purpose: "",
            workingFolderMode: .custom,
            workingFolderPath: "/tmp/example-project"
        )

        let reloaded = WorkspaceStore(persistenceURL: url)
        let unattached = try XCTUnwrap(reloaded.activeWorkspace.nodes.first(where: { $0.id == unattachedID }))
        let custom = try XCTUnwrap(reloaded.activeWorkspace.nodes.first(where: { $0.id == customID }))

        XCTAssertEqual(unattached.workingFolderMode, .unattached)
        XCTAssertNil(unattached.workingFolderPath)
        XCTAssertEqual(custom.workingFolderMode, .custom)
        XCTAssertEqual(custom.workingFolderPath, "/tmp/example-project")
    }

    func testPerSessionModelChoicePersists() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let nodeID = store.createSession(
            provider: .codex,
            name: "Model Owner",
            purpose: "implementation",
            agentModelID: "gpt-5.6-terra"
        )

        let reloaded = WorkspaceStore(persistenceURL: url)
        let node = try XCTUnwrap(reloaded.activeWorkspace.nodes.first(where: { $0.id == nodeID }))

        XCTAssertEqual(node.resolvedAgentModelID, "gpt-5.6-terra")
        XCTAssertEqual(node.subtitle, "Codex · GPT-5.6-Terra")
    }

    func testBrowserRestoresItsLastAddress() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let browserID = store.createSession(provider: .browser, name: "Research", purpose: "")
        XCTAssertTrue(store.updateNodeURL(browserID, url: "https://example.com/reference"))

        let reloaded = WorkspaceStore(persistenceURL: url)
        let browser = try XCTUnwrap(reloaded.activeWorkspace.nodes.first(where: { $0.id == browserID }))

        XCTAssertEqual(browser.url, "https://example.com/reference")
    }

    func testClosedSessionHistoryDoesNotInvalidateWorkspace() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.kind == .agent }))
        XCTAssertTrue(store.sendTask("Inspect the project", to: agent.id))
        store.removeNode(agent.id)

        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)

        XCTAssertEqual(loaded.source, .primary)
        XCTAssertFalse(loaded.state.workspaces[0].runHistory.isEmpty)
    }

    func testRemovedMissionAssigneeRemainsARecoverableBlockedReference() throws {
        let url = try temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
        let workerID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build the app",
            workerIDs: [workerID],
            reviewerID: nil
        ))
        store.removeNode(workerID)

        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)

        XCTAssertEqual(loaded.source, .primary)
        XCTAssertEqual(loaded.state.workspaces[0].missionHistory.first(where: { $0.id == missionID })?.tasks.first?.state, .blocked)
    }

    func testDuplicateNodeIdentityAcrossWorkspacesIsRejected() throws {
        let url = try temporaryURL()
        var invalid = WorkspaceStore.defaultState()
        var second = invalid.workspaces[0]
        second.id = UUID()
        second.name = "Duplicate IDs"
        invalid.workspaces.append(second)
        let encoder = JSONEncoder()
        try encoder.encode(invalid).write(to: url, options: .atomic)

        let loaded = WorkspacePersistence.load(from: url, seed: WorkspaceStore.defaultState)

        XCTAssertEqual(loaded.source, .seeded)
    }
}
