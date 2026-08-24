import Darwin
import Foundation
import SpatialAgentBridgeKit

@MainActor
final class TerminalSession: ObservableObject {
    enum SessionState: Equatable {
        case idle
        case running(pid_t)
        case exited(Int32)
        case failed(String)
    }

    @Published private(set) var output = ""
    @Published private(set) var state: SessionState = .idle

    let id: UUID
    let workingDirectory: URL

    private var masterFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var childPID: pid_t = 0
    private var bridgeCredential: AgentBridgeCredential?
    private let agentBridge: any SpatialAgentBridgeSessionProviding
    private let readQueue = DispatchQueue(label: "spatial-workspace.terminal-read", qos: .userInitiated)

    init(
        id: UUID,
        workingDirectory: URL,
        agentBridge: any SpatialAgentBridgeSessionProviding = SpatialAgentBridgeRuntime.shared
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.agentBridge = agentBridge
    }

    deinit {
        readSource?.cancel()
        if masterFileDescriptor >= 0 { Darwin.close(masterFileDescriptor) }
        if childPID > 0 { Darwin.kill(childPID, SIGHUP) }
        agentBridge.revoke(bridgeCredential)
    }

    func start() {
        guard case .idle = state else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            state = .failed("Working folder does not exist or is not a directory")
            return
        }

        var master: Int32 = -1
        var windowSize = winsize(ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        let credential = try? agentBridge.issueSession(
            nodeID: id,
            provider: "terminal",
            scopes: AgentBridgeSessionRegistry.allAudioScopes
        )
        let bridgeEnvironment = credential.map { agentBridge.environment(for: $0) } ?? [:]
        let inheritedBridgeKeys = ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("SPATIAL_AGENT_") }
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let shellArgument = strdup("-zsh")
        var shellArguments: [UnsafeMutablePointer<CChar>?] = [shellArgument, nil]
        defer { free(shellArgument) }
        let pid = forkpty(&master, nil, nil, &windowSize)

        if pid == 0 {
            guard Darwin.chdir(workingDirectory.path) == 0 else { _exit(126) }
            Darwin.setenv("TERM", "xterm-256color", 1)
            Darwin.setenv("COLORTERM", "truecolor", 1)
            for key in inheritedBridgeKeys {
                Darwin.unsetenv(key)
            }
            for (key, value) in bridgeEnvironment {
                Darwin.setenv(key, value, 1)
            }
            if let cliPath = bridgeEnvironment["SPATIAL_AGENT_CLI"] {
                let directory = URL(fileURLWithPath: cliPath).deletingLastPathComponent().path
                Darwin.setenv("PATH", "\(directory):\(inheritedPath)", 1)
            }
            _ = shellArguments.withUnsafeMutableBufferPointer { arguments in
                execv("/bin/zsh", arguments.baseAddress!)
            }
            _exit(127)
        }

        guard pid > 0, master >= 0 else {
            agentBridge.revoke(credential)
            state = .failed(String(cString: strerror(errno)))
            return
        }

        childPID = pid
        bridgeCredential = credential
        masterFileDescriptor = master
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        state = .running(pid)
        output = ""

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: readQueue)
        source.setEventHandler { [weak self] in self?.readAvailableBytes(from: master) }
        readSource = source
        source.resume()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            let result = waitpid(pid, &status, 0)
            guard result == pid else { return }
            let exitCode: Int32
            let signal = status & 0x7F
            if signal == 0 {
                exitCode = (status >> 8) & 0xFF
            } else if signal != 0x7F {
                exitCode = 128 + signal
            } else {
                exitCode = status
            }
            Task { @MainActor in self?.finish(exitCode: exitCode) }
        }
    }

    func send(_ text: String) {
        guard masterFileDescriptor >= 0, let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(masterFileDescriptor, base.advanced(by: written), bytes.count - written)
                if result > 0 {
                    written += result
                } else if errno != EAGAIN && errno != EINTR {
                    break
                }
            }
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        guard masterFileDescriptor >= 0 else { return }
        var size = winsize(ws_row: max(rows, 2), ws_col: max(columns, 10), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &size)
        if childPID > 0 { _ = Darwin.kill(childPID, SIGWINCH) }
    }

    func terminate() {
        guard childPID > 0 else { return }
        _ = Darwin.kill(childPID, SIGHUP)
    }

    private nonisolated func readAvailableBytes(from descriptor: Int32) {
        guard descriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var collected = Data()
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                collected.append(buffer, count: count)
            } else {
                break
            }
        }
        guard !collected.isEmpty else { return }
        let text = String(decoding: collected, as: UTF8.self)
        Task { @MainActor [weak self] in
            self?.append(TerminalText.clean(text))
        }
    }

    private func append(_ text: String) {
        output += text
        if output.count > 200_000 {
            output.removeFirst(output.count - 160_000)
        }
    }

    private func finish(exitCode: Int32) {
        readSource?.cancel()
        readSource = nil
        if masterFileDescriptor >= 0 {
            Darwin.close(masterFileDescriptor)
            masterFileDescriptor = -1
        }
        childPID = 0
        agentBridge.revoke(bridgeCredential)
        bridgeCredential = nil
        state = .exited(exitCode)
    }
}

@MainActor
final class TerminalRegistry {
    private var sessions: [UUID: TerminalSession] = [:]

    func session(id: UUID, workingDirectory: URL) -> TerminalSession {
        let requestedDirectory = workingDirectory.resolvingSymlinksInPath().standardizedFileURL
        if let existing = sessions[id],
           existing.workingDirectory.resolvingSymlinksInPath().standardizedFileURL == requestedDirectory {
            return existing
        }
        sessions.removeValue(forKey: id)?.terminate()
        let session = TerminalSession(id: id, workingDirectory: requestedDirectory)
        sessions[id] = session
        session.start()
        return session
    }

    func existingSession(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func remove(id: UUID) {
        sessions.removeValue(forKey: id)?.terminate()
    }

    func terminateAll() {
        for session in sessions.values { session.terminate() }
        sessions.removeAll()
    }
}

enum TerminalText {
    static func clean(_ text: String) -> String {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\u{1B}" {
                index = text.index(after: index)
                guard index < text.endIndex else { break }
                if text[index] == "[" {
                    index = text.index(after: index)
                    while index < text.endIndex {
                        let scalar = text[index].unicodeScalars.first?.value ?? 0
                        index = text.index(after: index)
                        if scalar >= 0x40 && scalar <= 0x7E { break }
                    }
                } else if text[index] == "]" {
                    index = text.index(after: index)
                    while index < text.endIndex {
                        if text[index] == "\u{7}" {
                            index = text.index(after: index)
                            break
                        }
                        index = text.index(after: index)
                    }
                }
                continue
            }
            if character != "\r" { result.append(character) }
            index = text.index(after: index)
        }
        return result
    }
}
