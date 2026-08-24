import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class SupervisorCommandTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }

    func testOneCommandOpensConfiguredAgents() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }

        store.execute("Open a Claude Code agent and a Codex agent")

        XCTAssertEqual(Set(store.activeWorkspace.nodes.map(\.title)), Set(["Marshall", "Skye"]))
        XCTAssertEqual(store.supervisorMessage, "Opened Claude Code and Codex")
    }

    func testCommandCanOpenMultipleSessionsFromTheSameProvider() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }

        store.execute("Open two Claude agents and two Codex agents")

        XCTAssertEqual(store.activeWorkspace.nodes.filter { $0.resolvedProvider == .claude }.count, 2)
        XCTAssertEqual(store.activeWorkspace.nodes.filter { $0.resolvedProvider == .codex }.count, 2)
        XCTAssertEqual(Set(store.activeWorkspace.nodes.map(\.title)).count, 4)
    }

    func testCompoundCommandSwitchesWorkspaceThenRefreshesItsBrowser() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        store.execute("Switch to Test App and refresh the browser")

        XCTAssertEqual(store.activeWorkspace.name, "Test App")
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.kind == .browser })?.revision, 1)
    }

    func testReplacingAgentPreservesSurroundingWorkspace() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        store.switchWorkspace(named: "Test")
        let browserID = store.activeWorkspace.nodes.first(where: { $0.kind == .browser })?.id

        store.execute("Close Builder, open a Codex agent, and prompt that Codex agent to make this landing page more aesthetic")

        XCTAssertFalse(store.activeWorkspace.nodes.contains(where: { $0.title == "Builder" }))
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: { $0.title == "Skye" && $0.status == .working }))
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: { $0.id == browserID }))
    }

    func testStateRoundTripsAcrossRelaunch() {
        let url = temporaryURL()
        let first = WorkspaceStore(persistenceURL: url)
        first.switchWorkspace(named: "Test")
        first.execute("Add the music player")

        let reloaded = WorkspaceStore(persistenceURL: url)

        XCTAssertEqual(reloaded.activeWorkspace.name, "Test App")
        XCTAssertTrue(reloaded.activeWorkspace.nodes.contains(where: { $0.kind == .music }))
    }

    func testOpeningBrowserReusesExistingNodeAndNavigatesIt() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
        let browserID = store.addNode(kind: .browser, title: "Preview", url: "https://example.com")
        store.minimizeNode(browserID)

        store.execute("Open the browser preview at https://cnvs.dev/demo")

        let browsers = store.activeWorkspace.nodes.filter { $0.kind == .browser }
        XCTAssertEqual(browsers.count, 1)
        XCTAssertEqual(browsers.first?.id, browserID)
        XCTAssertEqual(browsers.first?.url, "https://cnvs.dev/demo")
        XCTAssertFalse(browsers.first?.isMinimizedResolved ?? true)
    }

    func testOpeningMusicReusesExistingPlayerAndRestoresPlayableSource() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
        let musicID = store.addNode(kind: .music, title: "Focus")
        store.minimizeNode(musicID)

        store.execute("Open the music player")

        let players = store.activeWorkspace.nodes.filter { $0.kind == .music }
        XCTAssertEqual(players.count, 1)
        XCTAssertEqual(players.first?.id, musicID)
        XCTAssertEqual(players.first?.url, MusicStation.defaultURLString)
        XCTAssertFalse(players.first?.isMinimizedResolved ?? true)
    }

    func testFriendlyAgentNameRoutesWithoutProviderName() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        store.execute("Ask Marshall to explain the architecture")

        let marshall = store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })
        XCTAssertEqual(marshall?.status, .working)
        XCTAssertEqual(marshall?.content, "explain the architecture\n\n")
        XCTAssertEqual(store.promptDispatch?.targetNodeID, marshall?.id)
        XCTAssertEqual(store.promptDispatch?.summary, "explain the architecture")
    }

    func testFriendlyAgentNameDoesNotRequireDelegationVerb() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        store.execute("Marshall, review the persistence layer")

        let marshall = store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })
        XCTAssertEqual(marshall?.status, .working)
        XCTAssertEqual(marshall?.content, "review the persistence layer\n\n")
    }

    func testNewlyNamedNovaRoutesByItsAssignedName() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Review frontend changes")

        XCTAssertTrue(store.execute("Nova, inspect the workspace navigation"))

        let nova = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == novaID }))
        XCTAssertEqual(nova.status, .working)
        XCTAssertEqual(nova.content, "inspect the workspace navigation\n\n")
        XCTAssertEqual(store.latestRun(for: novaID)?.request, "inspect the workspace navigation")
        XCTAssertEqual(store.promptDispatch?.targetNodeID, novaID)
    }

    func testJarvisCanBeCreatedAndAddressedAsANamedParticipant() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        XCTAssertTrue(store.execute("Open a Jarvis session"))
        let jarvis = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .jarvis }))
        XCTAssertEqual(jarvis.title, "Jarvis")
        XCTAssertEqual(jarvis.content, "Ready as Jarvis")

        XCTAssertTrue(store.execute("Jarvis, give me the blunt version"))
        XCTAssertEqual(store.latestRun(for: jarvis.id)?.request, "give me the blunt version")
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == jarvis.id })?.chatHistory?.last?.content, "give me the blunt version")
    }

    func testOpeningJarvisAgainFocusesTheExistingParticipant() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        store.openJarvis()
        let jarvisID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .jarvis })?.id)
        store.minimizeNode(jarvisID)

        XCTAssertTrue(store.execute("Open a Jarvis session"))

        XCTAssertEqual(store.activeWorkspace.nodes.filter { $0.resolvedProvider == .jarvis }.count, 1)
        XCTAssertFalse(store.activeWorkspace.nodes.first(where: { $0.id == jarvisID })?.isMinimizedResolved ?? true)
        XCTAssertNil(store.latestRun(for: jarvisID), "Opening Jarvis should not send the creation command as a chat message")
    }

    func testAgentRuntimeGoalCarriesItsWorkspaceIdentity() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Review frontend changes")
        let nova = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == novaID }))

        let goal = WorkspaceStore.runtimeGoal(for: "Inspect the navigation", target: nova)

        XCTAssertTrue(goal.contains("Assigned workspace name: Nova"))
        XCTAssertTrue(goal.contains("Provider: Codex"))
        XCTAssertTrue(goal.contains("Assigned role: Review frontend changes"))
        XCTAssertTrue(goal.contains("If asked for your workspace name, answer “Nova.”"))
        XCTAssertTrue(goal.hasSuffix("Task:\nInspect the navigation"))
    }

    func testAgentNameMatchingUsesWordBoundaries() {
        XCTAssertTrue(WorkspaceStore.command("Nova, take this task", mentionsNodeNamed: "Nova"))
        XCTAssertTrue(WorkspaceStore.command("Send this to Nova please", mentionsNodeNamed: "Nova"))
        XCTAssertTrue(WorkspaceStore.command("Ask Front End to review", mentionsNodeNamed: "Front End"))
        XCTAssertFalse(WorkspaceStore.command("Update the database", mentionsNodeNamed: "Ada"))
    }

    func testNamedShellExplainsWhyItCannotReceiveAgentTasks() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        _ = store.createSession(provider: .shell, name: "Nova", purpose: "dev server")

        XCTAssertFalse(store.execute("Nova, inspect the workspace navigation"))

        XCTAssertTrue(store.supervisorMessage.contains("Nova is a shell terminal"))
        XCTAssertTrue(store.supervisorMessage.contains("Claude Code or Codex"))
    }

    func testTaskBeforeForMarshallRoutesAndPreservesTask() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        store.execute("Review the persistence layer for Marshall")

        let marshall = store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })
        XCTAssertEqual(marshall?.status, .working)
        XCTAssertEqual(marshall?.content, "Review the persistence layer\n\n")
    }

    func testInterruptedRunIsReconciledOnRelaunch() {
        let url = temporaryURL()
        let first = WorkspaceStore(persistenceURL: url)
        first.execute("Ask Marshall to keep working")

        let reloaded = WorkspaceStore(persistenceURL: url)
        let marshall = reloaded.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })

        XCTAssertEqual(marshall?.status, .needsAttention)
        XCTAssertTrue(marshall?.content.contains("Run interrupted when the app closed") == true)
        XCTAssertTrue(reloaded.supervisorMessage.contains("Recovered"))
    }

    func testProviderRoutingWrapperIsRemovedFromAgentGoal() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())

        store.execute("Prompt that Codex agent to make this landing page more aesthetic")

        let skye = store.activeWorkspace.nodes.first(where: { $0.title == "Skye" })
        XCTAssertEqual(skye?.content, "make this landing page more aesthetic\n\n")
    }

    func testAgentNodeComposerSendsLiteralTaskToItsAgent() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)

        XCTAssertTrue(store.sendTask("Review the persistence layer", to: marshallID))

        let marshall = store.activeWorkspace.nodes.first(where: { $0.id == marshallID })
        XCTAssertEqual(marshall?.content, "Review the persistence layer\n\n")
        XCTAssertEqual(marshall?.status, .working)
        let run = try XCTUnwrap(store.latestRun(for: marshallID))
        XCTAssertEqual(run.request, "Review the persistence layer")
        XCTAssertEqual(run.state, .working)
        XCTAssertNil(store.promptDispatch, "Inline agent composers should not animate from the workspace composer")
    }

    func testAgentNodeComposerQueuesSecondTaskWhileAgentIsWorking() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)
        XCTAssertTrue(store.sendTask("First task", to: marshallID))

        XCTAssertTrue(store.sendTask("Second task", to: marshallID))

        let marshall = store.activeWorkspace.nodes.first(where: { $0.id == marshallID })
        XCTAssertEqual(marshall?.content, "First task\n\n", "A queued task must not start a second run")
        XCTAssertEqual(marshall?.queuedPrompt, "Second task")
        XCTAssertTrue(store.supervisorMessage.contains("Queued"))

        // A later queued task replaces the earlier one — one pending slot, latest wins.
        XCTAssertTrue(store.sendTask("Third task", to: marshallID))
        XCTAssertEqual(
            store.activeWorkspace.nodes.first(where: { $0.id == marshallID })?.queuedPrompt,
            "Third task"
        )
    }

    func testSelectedAgentReceivesSentenceThatOnlyMentionsOpeningCodex() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)
        let codexCount = store.activeWorkspace.nodes.filter { $0.resolvedProvider == .codex }.count
        store.select(marshallID)

        XCTAssertTrue(store.execute("Open the Codex adapter and review how its arguments are built"))

        XCTAssertEqual(store.latestRun(for: marshallID)?.request, "Open the Codex adapter and review how its arguments are built")
        XCTAssertEqual(store.activeWorkspace.nodes.filter { $0.resolvedProvider == .codex }.count, codexCount)
    }

    func testExplicitWorkspaceCommandStillRunsWhenAgentIsSelected() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)
        let codexCount = store.activeWorkspace.nodes.filter { $0.resolvedProvider == .codex }.count
        store.select(marshallID)

        XCTAssertTrue(store.execute("Open a Codex agent"))

        XCTAssertEqual(store.activeWorkspace.nodes.filter { $0.resolvedProvider == .codex }.count, codexCount + 1)
        XCTAssertNil(store.latestRun(for: marshallID))
    }

    func testRejectedWorkspaceCommandRestoresExactDraft() {
        let store = WorkspaceStore(persistenceURL: temporaryURL())
        store.select(nil)
        store.commandText = "  Something ambiguous that should stay editable  "

        store.runCommand()

        XCTAssertEqual(store.commandText, "  Something ambiguous that should stay editable  ")
        XCTAssertTrue(store.supervisorMessage.contains("No matching workspace action"))
    }
}
