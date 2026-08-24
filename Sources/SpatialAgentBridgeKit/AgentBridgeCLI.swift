import Foundation

public enum AgentBridgeCLI {
    public static let usage = """
    Usage:
      spatial-agent audio status
      spatial-agent audio plan --intent <listen-privately|include-in-stream|exclude-from-stream|mute-source|apply-profile|set-bus> [target options] [--reason <text>]
      spatial-agent audio apply --plan <id> --revision <number> --idempotency <key>
      spatial-agent audio panic --idempotency <key> [--reason <text>]
      spatial-agent mcp

    Plan target options:
      --source <id>                 Source actions
      --profile <id>                apply-profile
      --bus <id> --enabled <true|false>  set-bus

    Authentication is supplied by CommandHall through the session environment.
    """

    @discardableResult
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        errorOutput: FileHandle = .standardError
    ) -> Int32 {
        guard let first = arguments.first, first != "--help", first != "-h" else {
            writeText(usage, to: output)
            return 0
        }
        if first == "mcp" {
            guard arguments.count == 1 else {
                writeUsageError("mcp does not accept command-line options", to: errorOutput)
                return 64
            }
            return runMCP(environment: environment, input: input, output: output)
        }
        guard first == "audio", arguments.count >= 2 else {
            writeUsageError("Expected an audio command or mcp", to: errorOutput)
            return 64
        }

        let command: AgentAudioCommand
        do {
            command = try parseAudioCommand(Array(arguments.dropFirst(2)), operationName: arguments[1])
        } catch let error as CLIError {
            writeUsageError(error.message, to: errorOutput)
            return 64
        } catch {
            writeUsageError("Command options are invalid", to: errorOutput)
            return 64
        }

        let request: AgentBridgeRequest
        let client: AgentBridgeClient
        do {
            let configured = try configuration(environment: environment)
            request = AgentBridgeRequest(auth: configured.authentication, command: command)
            client = AgentBridgeClient(socketURL: configured.socketURL)
        } catch let error as AgentBridgeErrorPayload {
            writeFailure(error, requestID: nil, to: errorOutput)
            return 78
        } catch {
            writeFailure(
                AgentBridgeErrorPayload(code: .authenticationRequired, message: "CommandHall agent session is not configured"),
                requestID: nil,
                to: errorOutput
            )
            return 78
        }

        do {
            let response = try client.send(request)
            writeResponse(response, to: output)
            return 0
        } catch let error as AgentBridgeErrorPayload {
            writeFailure(error, requestID: request.requestID, to: errorOutput)
            return exitCode(for: error.code)
        } catch {
            writeFailure(
                AgentBridgeErrorPayload(code: .internalError, message: "Spatial agent command failed", retryable: true),
                requestID: request.requestID,
                to: errorOutput
            )
            return 1
        }
    }

    public static func parseAudioCommand(_ arguments: [String], operationName: String) throws -> AgentAudioCommand {
        let options = try parseOptions(arguments)
        switch operationName {
        case AgentBridgeOperation.status.rawValue:
            guard options.isEmpty else { throw CLIError("status does not accept options") }
            return .status
        case AgentBridgeOperation.plan.rawValue:
            try requireOnly(options, allowed: ["intent", "source", "profile", "bus", "enabled", "reason"])
            guard let intentValue = options["intent"], let intent = AgentAudioIntent(rawValue: intentValue) else {
                throw CLIError("plan requires a recognized --intent")
            }
            let enabled: Bool?
            if let value = options["enabled"] {
                guard value == "true" || value == "false" else { throw CLIError("--enabled must be true or false") }
                enabled = value == "true"
            } else {
                enabled = nil
            }
            return .plan(
                AgentAudioPlanRequest(
                    intent: intent,
                    sourceID: options["source"],
                    profileID: options["profile"],
                    busID: options["bus"],
                    enabled: enabled,
                    reason: options["reason"]
                )
            )
        case AgentBridgeOperation.apply.rawValue:
            try requireOnly(options, allowed: ["plan", "revision", "idempotency"])
            guard let planID = options["plan"], let revisionText = options["revision"],
                  let revision = Int(revisionText), let idempotencyKey = options["idempotency"] else {
                throw CLIError("apply requires --plan, --revision, and --idempotency")
            }
            return .apply(AgentAudioApplyRequest(planID: planID, expectedRevision: revision, idempotencyKey: idempotencyKey))
        case AgentBridgeOperation.panic.rawValue:
            try requireOnly(options, allowed: ["idempotency", "reason"])
            guard let idempotencyKey = options["idempotency"] else {
                throw CLIError("panic requires --idempotency")
            }
            return .panic(AgentAudioPanicRequest(idempotencyKey: idempotencyKey, reason: options["reason"]))
        default:
            throw CLIError("Unknown audio operation \(operationName)")
        }
    }

    private struct Configuration {
        let socketURL: URL
        let authentication: AgentBridgeAuthentication
    }

    private struct CLIError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func configuration(environment: [String: String]) throws -> Configuration {
        guard let socketPath = environment[AgentBridgeEnvironment.socketPath], !socketPath.isEmpty,
              let sessionText = environment[AgentBridgeEnvironment.sessionID], let sessionID = UUID(uuidString: sessionText),
              let token = environment[AgentBridgeEnvironment.sessionToken], !token.isEmpty,
              let nodeText = environment[AgentBridgeEnvironment.nodeID], let nodeID = UUID(uuidString: nodeText),
              let provider = environment[AgentBridgeEnvironment.provider], !provider.isEmpty else {
            throw AgentBridgeErrorPayload(
                code: .authenticationRequired,
                message: "Run this command inside a CommandHall agent terminal"
            )
        }
        return Configuration(
            socketURL: URL(fileURLWithPath: socketPath),
            authentication: AgentBridgeAuthentication(sessionID: sessionID, token: token, nodeID: nodeID, provider: provider)
        )
    }

    private static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard option.hasPrefix("--"), option.count > 2 else {
                throw CLIError("Unexpected positional argument \(option)")
            }
            let key = String(option.dropFirst(2))
            guard options[key] == nil else { throw CLIError("Option --\(key) was provided more than once") }
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                throw CLIError("Option --\(key) requires a value")
            }
            options[key] = arguments[index]
            index += 1
        }
        return options
    }

    private static func requireOnly(_ options: [String: String], allowed: Set<String>) throws {
        if let unknown = Set(options.keys).subtracting(allowed).sorted().first {
            throw CLIError("Unknown option --\(unknown)")
        }
    }

    private static func runMCP(environment: [String: String], input: FileHandle, output: FileHandle) -> Int32 {
        let configured: Configuration
        do {
            configured = try configuration(environment: environment)
        } catch let error as AgentBridgeErrorPayload {
            writeMCPProtocolError(id: NSNull(), code: -32001, message: error.message, output: output)
            return 78
        } catch {
            writeMCPProtocolError(id: NSNull(), code: -32001, message: "CommandHall agent session is not configured", output: output)
            return 78
        }

        var buffered = Data()
        while true {
            let chunk: Data
            do {
                chunk = try input.read(upToCount: 4_096) ?? Data()
            } catch {
                return 1
            }
            if chunk.isEmpty {
                if !buffered.isEmpty { processMCPLine(buffered, configured: configured, output: output) }
                return 0
            }
            buffered.append(chunk)
            if buffered.count > AgentBridgeLimits.maximumRequestBytes {
                writeMCPProtocolError(id: NSNull(), code: -32600, message: "MCP request exceeded the size limit", output: output)
                return 1
            }
            while let newline = buffered.firstIndex(of: 0x0A) {
                let line = Data(buffered[..<newline])
                buffered.removeSubrange(...newline)
                if !line.isEmpty { processMCPLine(line, configured: configured, output: output) }
            }
        }
    }

    private static func processMCPLine(_ data: Data, configured: Configuration, output: FileHandle) {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            writeMCPProtocolError(id: NSNull(), code: -32600, message: "Invalid JSON-RPC request", output: output)
            return
        }
        let id = request["id"] ?? NSNull()
        if method.hasPrefix("notifications/") { return }

        switch method {
        case "initialize":
            writeMCPResult(
                id: id,
                result: [
                    "protocolVersion": "2025-03-26",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "spatial-agent-audio", "version": "1.0.0"],
                ],
                output: output
            )
        case "ping":
            writeMCPResult(id: id, result: [:], output: output)
        case "tools/list":
            writeMCPResult(id: id, result: ["tools": mcpTools], output: output)
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  Set(params.keys).isSubset(of: ["name", "arguments"]),
                  let name = params["name"] as? String,
                  let arguments = params["arguments"] as? [String: Any] else {
                writeMCPProtocolError(id: id, code: -32602, message: "Invalid tools/call parameters", output: output)
                return
            }
            do {
                let command = try mcpCommand(name: name, arguments: arguments)
                let bridgeRequest = AgentBridgeRequest(auth: configured.authentication, command: command)
                let response = try AgentBridgeClient(socketURL: configured.socketURL).send(bridgeRequest)
                let responseData = try AgentBridgeWireCodec.encodeResponse(response)
                let responseObject = try JSONSerialization.jsonObject(with: responseData)
                let text = String(decoding: responseData, as: UTF8.self)
                writeMCPResult(
                    id: id,
                    result: [
                        "content": [["type": "text", "text": text]],
                        "structuredContent": responseObject,
                        "isError": false,
                    ],
                    output: output
                )
            } catch let error as AgentBridgeErrorPayload {
                writeMCPResult(
                    id: id,
                    result: [
                        "content": [["type": "text", "text": error.message]],
                        "structuredContent": ["error": ["code": error.code.rawValue, "message": error.message, "retryable": error.retryable]],
                        "isError": true,
                    ],
                    output: output
                )
            } catch let error as CLIError {
                writeMCPProtocolError(id: id, code: -32602, message: error.message, output: output)
            } catch {
                writeMCPProtocolError(id: id, code: -32603, message: "Spatial audio tool failed", output: output)
            }
        default:
            writeMCPProtocolError(id: id, code: -32601, message: "Method not found", output: output)
        }
    }

    private static func mcpCommand(name: String, arguments: [String: Any]) throws -> AgentAudioCommand {
        switch name {
        case "audio_status":
            guard arguments.isEmpty else { throw CLIError("audio_status does not accept arguments") }
            return .status
        case "audio_plan":
            try requireMCPKeys(arguments, allowed: ["intent", "sourceId", "profileId", "busId", "enabled", "reason"])
            guard let rawIntent = arguments["intent"] as? String, let intent = AgentAudioIntent(rawValue: rawIntent) else {
                throw CLIError("audio_plan requires a recognized intent")
            }
            return .plan(
                AgentAudioPlanRequest(
                    intent: intent,
                    sourceID: arguments["sourceId"] as? String,
                    profileID: arguments["profileId"] as? String,
                    busID: arguments["busId"] as? String,
                    enabled: arguments["enabled"] as? Bool,
                    reason: arguments["reason"] as? String
                )
            )
        case "audio_apply":
            try requireMCPKeys(arguments, allowed: ["planId", "expectedRevision", "idempotencyKey"])
            guard let planID = arguments["planId"] as? String,
                  let revision = jsonInteger(arguments["expectedRevision"]),
                  let idempotencyKey = arguments["idempotencyKey"] as? String else {
                throw CLIError("audio_apply requires planId, expectedRevision, and idempotencyKey")
            }
            return .apply(AgentAudioApplyRequest(planID: planID, expectedRevision: revision, idempotencyKey: idempotencyKey))
        case "audio_panic":
            try requireMCPKeys(arguments, allowed: ["idempotencyKey", "reason"])
            guard let idempotencyKey = arguments["idempotencyKey"] as? String else {
                throw CLIError("audio_panic requires idempotencyKey")
            }
            return .panic(AgentAudioPanicRequest(idempotencyKey: idempotencyKey, reason: arguments["reason"] as? String))
        default:
            throw CLIError("Unknown Spatial audio tool")
        }
    }

    private static func requireMCPKeys(_ arguments: [String: Any], allowed: Set<String>) throws {
        if let unknown = Set(arguments.keys).subtracting(allowed).sorted().first {
            throw CLIError("Unknown argument \(unknown)")
        }
    }

    private static func jsonInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.rounded() == number.doubleValue else {
            return nil
        }
        return number.intValue
    }

    private static var mcpTools: [[String: Any]] {
        let noAdditional: [String: Any] = ["type": "object", "properties": [:], "additionalProperties": false]
        return [
            [
                "name": "audio_status",
                "description": "Read the authoritative Spatial audio routing and verification status.",
                "inputSchema": noAdditional,
                "annotations": ["readOnlyHint": true, "destructiveHint": false],
            ],
            [
                "name": "audio_plan",
                "description": "Create a bounded, reviewable plan for a semantic audio change. This does not apply it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "intent": ["type": "string", "enum": AgentAudioIntent.allCases.map(\.rawValue)],
                        "sourceId": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                        "profileId": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                        "busId": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                        "enabled": ["type": "boolean"],
                        "reason": ["type": "string", "maxLength": AgentBridgeLimits.maximumReasonLength],
                    ],
                    "required": ["intent"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": true, "destructiveHint": false],
            ],
            [
                "name": "audio_apply",
                "description": "Apply an unexpired server-created audio plan using its expected revision and idempotency key.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "planId": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                        "expectedRevision": ["type": "integer", "minimum": 0],
                        "idempotencyKey": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                    ],
                    "required": ["planId", "expectedRevision", "idempotencyKey"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": true],
            ],
            [
                "name": "audio_panic",
                "description": "Immediately request the allowlisted panic-mute safety action.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "idempotencyKey": ["type": "string", "maxLength": AgentBridgeLimits.maximumIdentifierLength],
                        "reason": ["type": "string", "maxLength": AgentBridgeLimits.maximumReasonLength],
                    ],
                    "required": ["idempotencyKey"],
                    "additionalProperties": false,
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": true],
            ],
        ]
    }

    private static func exitCode(for code: AgentBridgeErrorCode) -> Int32 {
        switch code {
        case .authenticationRequired, .invalidSession, .sessionExpired, .identityMismatch, .forbidden: 77
        case .notReady, .handlerUnavailable: 69
        case .invalidJSON, .invalidRequest, .conflict: 65
        case .rateLimited: 75
        case .internalError: 1
        }
    }

    private static func writeUsageError(_ message: String, to handle: FileHandle) {
        writeText("\(message)\n\n\(usage)", to: handle)
    }

    private static func writeFailure(_ error: AgentBridgeErrorPayload, requestID: UUID?, to handle: FileHandle) {
        writeResponse(.failure(requestID: requestID, error: error), to: handle)
    }

    private static func writeResponse(_ response: AgentBridgeResponse, to handle: FileHandle) {
        if let data = try? AgentBridgeWireCodec.encodeResponse(response) {
            handle.write(data + Data([0x0A]))
        }
    }

    private static func writeText(_ text: String, to handle: FileHandle) {
        handle.write(Data((text + "\n").utf8))
    }

    private static func writeMCPResult(id: Any, result: Any, output: FileHandle) {
        writeMCPObject(["jsonrpc": "2.0", "id": id, "result": result], output: output)
    }

    private static func writeMCPProtocolError(id: Any, code: Int, message: String, output: FileHandle) {
        writeMCPObject(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]], output: output)
    }

    private static func writeMCPObject(_ object: [String: Any], output: FileHandle) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        output.write(data + Data([0x0A]))
    }
}
