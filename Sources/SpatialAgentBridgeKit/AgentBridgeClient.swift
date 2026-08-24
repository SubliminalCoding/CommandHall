import Darwin
import Foundation

public final class AgentBridgeClient: @unchecked Sendable {
    public let socketURL: URL

    public init(socketURL: URL) {
        self.socketURL = socketURL.standardizedFileURL
    }

    public func send(_ request: AgentBridgeRequest) throws -> AgentBridgeResponse {
        try validateSocketOwnership()
        var address = try AgentBridgeBroker.socketAddress(path: socketURL.path)
        let addressLength = socklen_t(address.sun_len)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentBridgeErrorPayload(code: .notReady, message: "Could not open the Spatial agent bridge", retryable: true)
        }
        defer { Darwin.close(descriptor) }
        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard connected == 0 else {
            throw AgentBridgeErrorPayload(code: .notReady, message: "CommandHall audio controls are unavailable", retryable: true)
        }

        let requestData = try AgentBridgeWireCodec.encodeRequest(request) + Data([0x0A])
        AgentBridgeBroker.writeAll(requestData, to: descriptor)
        _ = Darwin.shutdown(descriptor, SHUT_WR)
        let responseData = try AgentBridgeBroker.readMessage(from: descriptor, maximumBytes: AgentBridgeLimits.maximumResponseBytes)
        let response = try AgentBridgeWireCodec.decodeResponse(responseData)
        if let error = response.error {
            guard response.requestID == nil || response.requestID == request.requestID else {
                throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Bridge error response did not match the request")
            }
            throw error
        }
        guard response.requestID == request.requestID else {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Bridge response did not match the request")
        }
        return response
    }

    private func validateSocketOwnership() throws {
        var socketInfo = stat()
        let path = socketURL.path
        guard Darwin.lstat(path, &socketInfo) == 0,
              socketInfo.st_uid == Darwin.getuid(),
              (socketInfo.st_mode & S_IFMT) == S_IFSOCK,
              (socketInfo.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0 else {
            throw AgentBridgeErrorPayload(code: .notReady, message: "CommandHall agent bridge socket is missing or insecure", retryable: true)
        }
        var directoryInfo = stat()
        let directory = socketURL.deletingLastPathComponent().path
        guard Darwin.lstat(directory, &directoryInfo) == 0,
              directoryInfo.st_uid == Darwin.getuid(),
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              (directoryInfo.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0 else {
            throw AgentBridgeErrorPayload(code: .notReady, message: "CommandHall agent bridge directory is insecure", retryable: true)
        }
    }
}
