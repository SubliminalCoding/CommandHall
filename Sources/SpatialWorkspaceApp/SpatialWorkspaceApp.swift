import SwiftUI

@main
struct SpatialWorkspaceApp: App {
    @StateObject private var store: WorkspaceStore
    @StateObject private var signalDeck = SignalDeckController()
    @AppStorage(JarvisBackend.kindKey) private var jarvisBackend = JarvisBackendKind.hq.rawValue
    private let smokeTest: Bool

    init() {
        let smokeTest = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        self.smokeTest = smokeTest
        let smokePersistence = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-workspace-smoke-\(ProcessInfo.processInfo.processIdentifier).json")
        _store = StateObject(wrappedValue: WorkspaceStore(
            persistenceURL: smokeTest ? smokePersistence : nil,
            runtimeEnabled: !smokeTest
        ))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceRootView(
                store: store,
                signalDeckController: signalDeck,
                configuration: smokeTest ? .visualTest() : .live
            )
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    if smokeTest {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            NSApplication.shared.terminate(nil)
                        }
                        return
                    }
                    SignalDeckAgentBridgeConnection.install(controller: signalDeck)
                    signalDeck.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Claude Code Agent") { store.openClaudeAgent() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Codex Agent") { store.openCodexAgent() }
                Button("New Note") { store.addNode(kind: .note) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Preview") { store.addNode(kind: .preview) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("New Live Chat") { store.addNode(kind: .liveChat, title: "Live Chat") }
                Button("New Named Terminal") {
                    _ = store.createSession(
                        provider: .shell,
                        name: store.suggestedSessionName(for: .shell),
                        purpose: "",
                        workingFolderMode: .unattached
                    )
                }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Jarvis") {
                Picker("Model backend", selection: $jarvisBackend) {
                    ForEach(JarvisBackendKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
            }
        }
    }
}
