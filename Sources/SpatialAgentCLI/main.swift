import Darwin
import SpatialAgentBridgeKit

let exitCode = AgentBridgeCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
Darwin.exit(exitCode)
