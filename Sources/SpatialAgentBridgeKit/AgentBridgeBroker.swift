import Darwin
import Foundation

public final class AgentAudioControlRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (any AgentAudioControlHandling)?

    public init(handler: (any AgentAudioControlHandling)? = nil) {
        self.handler = handler
    }

    public func install(_ handler: (any AgentAudioControlHandling)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func dispatch(_ command: AgentAudioCommand, identity: AgentBridgeSessionIdentity) async throws -> AgentAudioResult {
        let currentHandler = installedHandler()
        guard let currentHandler else {
            throw AgentBridgeHandlerError(
                code: .handlerUnavailable,
                message: "CommandHall has not connected its audio controller yet",
                retryable: true
            )
        }
        return try await currentHandler.handle(command, for: identity)
    }

    private func installedHandler() -> (any AgentAudioControlHandling)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

public enum AgentBridgeBrokerError: Error, Equatable {
    case invalidSocketPath
    case insecureSocketDirectory
    case alreadyRunning
    case systemCall(String)
}

public final class AgentBridgeBroker: @unchecked Sendable {
    public let socketURL: URL

    private let registry: AgentBridgeSessionRegistry
    private let router: AgentAudioControlRouter
    private let lifecycleLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "spatial-workspace.agent-bridge.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "spatial-workspace.agent-bridge.client", qos: .userInitiated, attributes: .concurrent)
    private var listener: DispatchSourceRead?

    public init(socketURL: URL, registry: AgentBridgeSessionRegistry, router: AgentAudioControlRouter) {
        self.socketURL = socketURL.standardizedFileURL
        self.registry = registry
        self.router = router
    }

    deinit {
        stop()
    }

    public func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard listener == nil else { return }

        try Self.prepareSocketDirectory(socketURL.deletingLastPathComponent())
        try Self.removeStaleSocketIfSafe(socketURL)
        var address = try Self.socketAddress(path: socketURL.path)
        let addressLength = socklen_t(address.sun_len)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentBridgeBrokerError.systemCall("socket: \(Self.currentError())")
        }
        var shouldClose = true
        defer { if shouldClose { Darwin.close(descriptor) } }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                Darwin.bind(descriptor, socketPointer, addressLength)
            }
        }
        guard bindResult == 0 else {
            throw AgentBridgeBrokerError.systemCall("bind: \(Self.currentError())")
        }
        guard Darwin.chmod(socketURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            _ = Darwin.unlink(socketURL.path)
            throw AgentBridgeBrokerError.systemCall("chmod: \(Self.currentError())")
        }
        guard Darwin.listen(descriptor, 32) == 0 else {
            _ = Darwin.unlink(socketURL.path)
            throw AgentBridgeBrokerError.systemCall("listen: \(Self.currentError())")
        }
        _ = Darwin.fcntl(descriptor, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptClients(from: descriptor) }
        source.setCancelHandler { [socketURL] in
            Darwin.close(descriptor)
            _ = Darwin.unlink(socketURL.path)
        }
        listener = source
        shouldClose = false
        source.resume()
    }

    public func stop() {
        lifecycleLock.lock()
        let source = listener
        listener = nil
        lifecycleLock.unlock()
        source?.cancel()
    }

    public var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return listener != nil
    }

    private func acceptClients(from listenerDescriptor: Int32) {
        while true {
            let client = Darwin.accept(listenerDescriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            clientQueue.async { [weak self] in self?.handleClient(client) }
        }
    }

    private func handleClient(_ descriptor: Int32) {
        defer { Darwin.close(descriptor) }
        let descriptorFlags = Darwin.fcntl(descriptor, F_GETFL)
        if descriptorFlags >= 0 {
            _ = Darwin.fcntl(descriptor, F_SETFL, descriptorFlags & ~O_NONBLOCK)
        }
        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        guard Self.peerIsCurrentUser(descriptor) else {
            write(
                .failure(
                    requestID: nil,
                    error: AgentBridgeErrorPayload(code: .forbidden, message: "Bridge connections must come from the CommandHall owner")
                ),
                to: descriptor
            )
            return
        }

        let requestData: Data
        do {
            requestData = try Self.readMessage(from: descriptor, maximumBytes: AgentBridgeLimits.maximumRequestBytes)
        } catch let error as AgentBridgeErrorPayload {
            write(.failure(requestID: nil, error: error), to: descriptor)
            return
        } catch {
            write(
                .failure(requestID: nil, error: AgentBridgeErrorPayload(code: .invalidJSON, message: "Could not read the bridge request")),
                to: descriptor
            )
            return
        }

        let request: AgentBridgeRequest
        do {
            request = try AgentBridgeWireCodec.decodeRequest(requestData)
        } catch let error as AgentBridgeErrorPayload {
            write(.failure(requestID: nil, error: error), to: descriptor)
            return
        } catch {
            write(
                .failure(requestID: nil, error: AgentBridgeErrorPayload(code: .invalidRequest, message: "Request did not match the bridge schema")),
                to: descriptor
            )
            return
        }

        let identity: AgentBridgeSessionIdentity
        do {
            identity = try registry.authorize(request.auth, operation: request.command.operation)
        } catch let error as AgentBridgeErrorPayload {
            write(.failure(requestID: request.requestID, error: error), to: descriptor)
            return
        } catch {
            write(
                .failure(requestID: request.requestID, error: AgentBridgeErrorPayload(code: .invalidSession, message: "Agent session could not be authorized")),
                to: descriptor
            )
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var response: AgentBridgeResponse?
        Task {
            do {
                let result = try await router.dispatch(request.command, identity: identity)
                guard result.matches(request.command.operation) else {
                    throw AgentBridgeHandlerError(code: .internalError, message: "Audio controller returned the wrong result type")
                }
                response = .success(requestID: request.requestID, result: result)
            } catch let error as AgentBridgeHandlerError {
                response = .failure(requestID: request.requestID, error: error.payload)
            } catch let error as AgentBridgeErrorPayload {
                response = .failure(requestID: request.requestID, error: error)
            } catch {
                response = .failure(
                    requestID: request.requestID,
                    error: AgentBridgeErrorPayload(code: .internalError, message: "Audio controller could not complete the request", retryable: true)
                )
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success, let response else {
            write(
                .failure(
                    requestID: request.requestID,
                    error: AgentBridgeErrorPayload(code: .notReady, message: "Audio controller timed out", retryable: true)
                ),
                to: descriptor
            )
            return
        }
        write(response, to: descriptor)
    }

    private func write(_ response: AgentBridgeResponse, to descriptor: Int32) {
        let data: Data
        do {
            data = try AgentBridgeWireCodec.encodeResponse(response) + Data([0x0A])
        } catch {
            let fallback = #"{"error":{"code":"internal_error","message":"Bridge response encoding failed","retryable":true},"ok":false,"requestId":null,"version":1}"#
            Self.writeAll(Data(fallback.utf8) + Data([0x0A]), to: descriptor)
            return
        }
        Self.writeAll(data, to: descriptor)
    }

    private static func prepareSocketDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard Darwin.chmod(directory.path, mode_t(S_IRWXU)) == 0 else {
            throw AgentBridgeBrokerError.systemCall("chmod directory: \(currentError())")
        }
        var info = stat()
        guard Darwin.lstat(directory.path, &info) == 0,
              info.st_uid == Darwin.getuid(),
              (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0 else {
            throw AgentBridgeBrokerError.insecureSocketDirectory
        }
    }

    private static func removeStaleSocketIfSafe(_ socketURL: URL) throws {
        var info = stat()
        guard Darwin.lstat(socketURL.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw AgentBridgeBrokerError.systemCall("lstat: \(currentError())")
        }
        guard info.st_uid == Darwin.getuid(), (info.st_mode & S_IFMT) == S_IFSOCK else {
            throw AgentBridgeBrokerError.insecureSocketDirectory
        }
        if canConnect(to: socketURL.path) {
            throw AgentBridgeBrokerError.alreadyRunning
        }
        guard Darwin.unlink(socketURL.path) == 0 else {
            throw AgentBridgeBrokerError.systemCall("unlink stale socket: \(currentError())")
        }
    }

    private static func canConnect(to path: String) -> Bool {
        guard var address = try? socketAddress(path: path) else { return false }
        let addressLength = socklen_t(address.sun_len)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength) == 0
            }
        }
    }

    static func socketAddress(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw AgentBridgeBrokerError.invalidSocketPath }
        address.sun_family = sa_family_t(AF_UNIX)
        let offset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path) ?? 0
        address.sun_len = UInt8(offset + bytes.count)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in bytes.enumerated() { destination[index] = byte }
            }
        }
        return address
    }

    static func peerIsCurrentUser(_ descriptor: Int32) -> Bool {
        var userID: uid_t = 0
        var groupID: gid_t = 0
        return Darwin.getpeereid(descriptor, &userID, &groupID) == 0 && userID == Darwin.getuid()
    }

    static func readMessage(from descriptor: Int32, maximumBytes: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count <= maximumBytes {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                if let newline = buffer[..<count].firstIndex(of: 0x0A) {
                    data.append(buffer, count: newline)
                    return data
                }
                data.append(buffer, count: count)
                continue
            }
            if count == 0 { return data }
            if errno == EINTR { continue }
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Bridge request could not be read")
        }
        throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Bridge request exceeded the size limit")
    }

    static func writeAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                } else if errno != EINTR {
                    return
                }
            }
        }
    }

    static func currentError() -> String {
        String(cString: strerror(errno))
    }
}

private extension AgentAudioResult {
    func matches(_ operation: AgentBridgeOperation) -> Bool {
        switch (self, operation) {
        case (.status, .status), (.plan, .plan), (.applied, .apply), (.panic, .panic): true
        default: false
        }
    }
}
