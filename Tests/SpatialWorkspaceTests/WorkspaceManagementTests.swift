import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspaceManagementTests: XCTestCase {
    private func store() -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        return WorkspaceStore(persistenceURL: url)
    }

    func testCreateRenameSwitchAndDeleteWorkspace() {
        let store = store()
        let originalID = store.activeWorkspace.id

        store.createWorkspace(name: "Project", rootPath: "/tmp/project")
        let createdID = store.activeWorkspace.id
        XCTAssertNotEqual(createdID, originalID)
        XCTAssertEqual(store.activeWorkspace.rootPath, "/tmp/project")

        store.renameActiveWorkspace(to: "Client Work")
        XCTAssertEqual(store.activeWorkspace.name, "Client Work")

        store.switchWorkspace(to: originalID)
        XCTAssertEqual(store.activeWorkspace.id, originalID)
        store.switchWorkspace(to: createdID)
        XCTAssertEqual(store.activeWorkspace.id, createdID)

        XCTAssertTrue(store.deleteActiveWorkspace())
        XCTAssertFalse(store.state.workspaces.contains(where: { $0.id == createdID }))
        XCTAssertNotEqual(store.activeWorkspace.id, createdID)
    }

    func testDuplicateNamesReceiveStableSuffixes() {
        let store = store()
        store.createWorkspace(name: "Project", rootPath: "/tmp/one")
        store.createWorkspace(name: "Project", rootPath: "/tmp/two")
        XCTAssertEqual(store.activeWorkspace.name, "Project 2")
    }

    func testLastWorkspaceCannotBeDeleted() {
        let store = store()
        while store.state.workspaces.count > 1 { XCTAssertTrue(store.deleteActiveWorkspace()) }
        XCTAssertFalse(store.deleteActiveWorkspace())
        XCTAssertEqual(store.state.workspaces.count, 1)
    }

    func testDuplicateWorkspaceCopiesLayoutWithoutSharingRuntimeIdentity() {
        let store = store()
        let source = store.activeWorkspace

        store.duplicateActiveWorkspace()

        XCTAssertEqual(store.activeWorkspace.name, "\(source.name) Copy")
        XCTAssertEqual(store.activeWorkspace.rootPath, source.rootPath)
        XCTAssertEqual(store.activeWorkspace.camera, source.camera)
        XCTAssertEqual(store.activeWorkspace.nodes.map(\.title), source.nodes.map(\.title))
        XCTAssertTrue(Set(store.activeWorkspace.nodes.map(\.id)).isDisjoint(with: Set(source.nodes.map(\.id))))
        XCTAssertTrue(store.activeWorkspace.nodes.allSatisfy { $0.sessionID == nil })
    }

    func testMultipleProviderSessionsHaveUniqueNamesAndStableProviders() {
        let store = store()
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }

        let first = store.createSession(provider: .claude, name: "Marshall", purpose: "frontend")
        let second = store.createSession(provider: .claude, name: "Marshall", purpose: "review")
        let terminal = store.createSession(provider: .shell, name: "Web server", purpose: "dev server")

        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == first })?.title, "Marshall")
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == second })?.title, "Marshall 2")
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == second })?.resolvedProvider, .claude)
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == terminal })?.title, "Web server")
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == terminal })?.purpose, "dev server")
    }

    func testCodingSessionsStoreProviderSpecificModelChoices() throws {
        let store = store()
        let claudeID = store.createSession(
            provider: .claude,
            name: "Ada",
            purpose: "architecture",
            agentModelID: "opus"
        )
        let codexID = store.createSession(
            provider: .codex,
            name: "Nova",
            purpose: "implementation",
            agentModelID: "gpt-5.6-sol"
        )
        let shellID = store.createSession(
            provider: .shell,
            name: "Build",
            purpose: "tests",
            agentModelID: "must-not-apply"
        )

        let claude = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == claudeID }))
        let codex = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == codexID }))
        let shell = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == shellID }))

        XCTAssertEqual(claude.resolvedAgentModelID, "opus")
        XCTAssertEqual(claude.subtitle, "Claude Code · Opus")
        XCTAssertEqual(codex.resolvedAgentModelID, "gpt-5.6-sol")
        XCTAssertEqual(codex.subtitle, "Codex · GPT-5.6-Sol")
        XCTAssertNil(shell.resolvedAgentModelID)
        XCTAssertEqual(shell.subtitle, "Terminal")
    }

    func testAgentModelIDsRejectWhitespaceAndShellMetacharacters() {
        XCTAssertNil(AgentModelCatalog.normalizedModelID("   "))
        XCTAssertNil(AgentModelCatalog.normalizedModelID("gpt-5.6-sol; touch /tmp/nope"))
        XCTAssertEqual(AgentModelCatalog.normalizedModelID("openai/gpt-5.6-sol:latest"), "openai/gpt-5.6-sol:latest")
    }

    func testNewSessionCanStartUnattachedOrInAnExplicitFolder() throws {
        let store = store()
        let workspaceRoot = try XCTUnwrap(store.activeWorkspace.rootPath)
        let unattachedID = store.createSession(
            provider: .shell,
            name: "Scratch",
            purpose: "",
            workingFolderMode: .unattached
        )
        let unattached = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == unattachedID }))
        let scratchDirectory = store.sessionWorkingDirectory(for: unattachedID)

        XCTAssertEqual(unattached.workingFolderMode, .unattached)
        XCTAssertNil(unattached.workingFolderPath)
        XCTAssertEqual(store.sessionWorkingFolderLabel(for: unattachedID), "No folder")
        XCTAssertNotEqual(scratchDirectory.path, workspaceRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratchDirectory.path))

        let customDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        let customID = store.createSession(
            provider: .codex,
            name: "Project Agent",
            purpose: "",
            workingFolderMode: .custom,
            workingFolderPath: customDirectory.path
        )
        let custom = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == customID }))

        XCTAssertEqual(custom.workingFolderMode, .custom)
        XCTAssertEqual(custom.workingFolderPath, customDirectory.path)
        XCTAssertEqual(store.sessionWorkingDirectory(for: customID), customDirectory.resolvingSymlinksInPath().standardizedFileURL)
    }

    func testMissingCustomFolderFallsBackToUnattached() throws {
        let store = store()
        let id = store.createSession(
            provider: .claude,
            name: "Unbound",
            purpose: "",
            workingFolderMode: .custom,
            workingFolderPath: "   "
        )
        let node = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == id }))

        XCTAssertEqual(node.workingFolderMode, .unattached)
        XCTAssertNil(node.workingFolderPath)
        XCTAssertEqual(store.sessionWorkingFolderLabel(for: id), "No folder")
    }

    func testNodeRenamePreservesIdentityAndProvider() {
        let store = store()
        let id = store.createSession(provider: .codex, name: "Skye", purpose: "tests")

        store.renameNode(id, to: "Nova")

        let renamed = store.activeWorkspace.nodes.first(where: { $0.id == id })
        XCTAssertEqual(renamed?.title, "Nova")
        XCTAssertEqual(renamed?.resolvedProvider, .codex)
        XCTAssertEqual(renamed?.purpose, "tests")
    }

    func testAddingSessionAutomaticallyRegroupsTheWorkspace() {
        let store = store()
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
        store.updateViewportSize(CGSize(width: 1_440, height: 900))

        _ = store.createSession(provider: .claude, name: "Marshall", purpose: "frontend")
        _ = store.createSession(provider: .codex, name: "Skye", purpose: "review")
        _ = store.createSession(provider: .shell, name: "Web server", purpose: "dev server")

        let nodes = store.activeWorkspace.nodes
        XCTAssertEqual(nodes.count, 3)
        XCTAssertTrue(nodes.allSatisfy { $0.size == nodes[0].size })
        XCTAssertEqual(Set(nodes.map(\.position.y)).count, 1)
        XCTAssertTrue(nodes[0].position.x < nodes[1].position.x)
        XCTAssertTrue(nodes[1].position.x < nodes[2].position.x)
        XCTAssertLessThan(store.activeWorkspace.camera.scale, 1)
    }

    func testFillLayoutAndBackgroundPersistAcrossRelaunchAndNewSessions() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let first = WorkspaceStore(persistenceURL: url)
        for node in first.activeWorkspace.nodes { first.removeNode(node.id) }
        first.updateViewportSize(CGSize(width: 1_440, height: 900))
        _ = first.createSession(provider: .claude, name: "Marshall", purpose: "")
        _ = first.createSession(provider: .codex, name: "Skye", purpose: "")
        first.arrangeNodes(mode: .fill)
        first.setTheme(.skyIsles)
        _ = first.createSession(provider: .shell, name: "Build", purpose: "")

        XCTAssertEqual(first.activeWorkspace.resolvedLayoutMode, .fill)
        XCTAssertEqual(first.activeWorkspace.nodes.first?.position.x, 0)
        let last = try? XCTUnwrap(first.activeWorkspace.nodes.last)
        XCTAssertEqual((last?.position.x ?? 0) + (last?.size.width ?? 0), 1_340, accuracy: 0.001)
        XCTAssertEqual(first.activeWorkspace.camera.offset.x, 76, accuracy: 0.001)

        let reloaded = WorkspaceStore(persistenceURL: url)
        XCTAssertEqual(reloaded.activeWorkspace.resolvedLayoutMode, .fill)
        XCTAssertEqual(WorkspaceTheme.resolve(reloaded.activeWorkspace.theme), .skyIsles)
    }

    func testBackgroundCatalogHasDistinctStableChoices() {
        let themes = WorkspaceTheme.allCases

        XCTAssertEqual(themes.count, 8)
        XCTAssertEqual(Set(themes.map(\.rawValue)).count, themes.count)
        XCTAssertEqual(Set(themes.map(\.label)).count, themes.count)
        XCTAssertEqual(Set(themes.map(\.symbol)).count, themes.count)
        XCTAssertEqual(WorkspaceTheme.resolve("luminous-abyss"), .nocturne)
    }

    func testMinimizedSessionsStayAliveAndVisibleSessionsReflow() {
        let store = store()
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
        store.updateViewportSize(CGSize(width: 1_440, height: 900))
        let marshall = store.createSession(provider: .claude, name: "Marshall", purpose: "frontend")
        let skye = store.createSession(provider: .codex, name: "Skye", purpose: "review")
        let build = store.createSession(provider: .shell, name: "Build", purpose: "tests")

        store.minimizeNode(skye)

        XCTAssertEqual(store.minimizedNodes.map(\.id), [skye])
        XCTAssertEqual(Set(store.visibleNodes.map(\.id)), Set([marshall, build]))
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == skye })?.resolvedProvider, .codex)
        XCTAssertEqual(store.visibleNodes[0].position.y, store.visibleNodes[1].position.y)

        store.restoreNode(skye)
        XCTAssertTrue(store.minimizedNodes.isEmpty)
        XCTAssertEqual(store.visibleNodes.count, 3)
        XCTAssertEqual(store.selectedNodeID, skye)
    }

    func testMinimizeAllSupportsMixAndMatchRestore() throws {
        let store = store()
        let total = store.activeWorkspace.nodes.count

        store.minimizeAllNodes()
        XCTAssertTrue(store.visibleNodes.isEmpty)
        XCTAssertEqual(store.minimizedNodes.count, total)

        let restoredID = try XCTUnwrap(store.minimizedNodes.first?.id)
        store.restoreNode(restoredID)
        XCTAssertEqual(store.visibleNodes.map(\.id), [restoredID])
        XCTAssertEqual(store.minimizedNodes.count, total - 1)

        store.restoreAllNodes()
        XCTAssertEqual(store.visibleNodes.count, total)
        XCTAssertTrue(store.minimizedNodes.isEmpty)
    }

    func testMinimizedStatePersistsAcrossRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let first = WorkspaceStore(persistenceURL: url)
        let nodeID = try XCTUnwrap(first.activeWorkspace.nodes.first?.id)
        first.minimizeNode(nodeID)

        let reloaded = WorkspaceStore(persistenceURL: url)
        XCTAssertEqual(reloaded.minimizedNodes.map(\.id), [nodeID])
        XCTAssertFalse(reloaded.visibleNodes.contains(where: { $0.id == nodeID }))
    }

    func testSendingTaskToMinimizedAgentRestoresIt() throws {
        let store = store()
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.kind == .agent }))
        store.minimizeNode(agent.id)

        XCTAssertTrue(store.sendTask("Create a compact status view", to: agent.id))

        XCTAssertTrue(store.visibleNodes.contains(where: { $0.id == agent.id }))
        XCTAssertFalse(store.minimizedNodes.contains(where: { $0.id == agent.id }))
        XCTAssertEqual(store.latestRun(for: agent.id)?.request, "Create a compact status view")
    }
}
