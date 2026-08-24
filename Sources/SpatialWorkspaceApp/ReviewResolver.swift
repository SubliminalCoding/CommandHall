import Foundation

enum ReviewResolver {
    static func isWithinWorkspace(_ artifact: WorkspaceArtifact, rootPath: String) -> Bool {
        guard artifact.kind != .url else { return true }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let file = URL(fileURLWithPath: artifact.location).resolvingSymlinksInPath().standardizedFileURL
        return file.path == root.path || file.path.hasPrefix(root.path + "/")
    }

    static func previewURL(for artifact: WorkspaceArtifact, rootPath: String) -> String? {
        guard artifact.kind.supportsEmbeddedPreview else { return nil }
        if artifact.kind == .url { return artifact.location }
        guard isWithinWorkspace(artifact, rootPath: rootPath) else { return nil }
        return URL(fileURLWithPath: artifact.location).resolvingSymlinksInPath().standardizedFileURL.absoluteString
    }

    static func detail(for artifact: WorkspaceArtifact, rootPath: String) -> String {
        guard artifact.kind != .url else {
            return "Live URL\n\(artifact.location)"
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let file = URL(fileURLWithPath: artifact.location).resolvingSymlinksInPath().standardizedFileURL
        guard isWithinWorkspace(artifact, rootPath: rootPath) else {
            return "This artifact is outside the workspace. Open it explicitly to inspect it."
        }

        if let diff = gitDiff(file: file, root: root), !diff.isEmpty {
            return diff
        }
        guard let data = try? Data(contentsOf: file) else {
            return "The file is no longer available at:\n\(file.path)"
        }
        guard data.count <= 180_000 else {
            return "\(artifact.title) is \(data.count.formatted()) bytes. Use Open or Reveal in Finder to inspect the complete file."
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "Binary artifact\n\(artifact.title)\n\(data.count.formatted()) bytes"
    }

    private static func gitDiff(file: URL, root: URL) -> String? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { return nil }
        let relative = String(file.path.dropFirst(min(file.path.count, root.path.count + 1)))
        do {
            let diff = try runGit(root: root, arguments: ["diff", "--no-ext-diff", "--unified=3", "--", relative])
            guard diff.status == 0 else { return nil }
            let value = diff.text
            if !value.isEmpty { return value }

            let status = try runGit(root: root, arguments: ["status", "--porcelain", "--", relative])
            return status.text.hasPrefix("??") ? nil : value
        } catch {
            return nil
        }
    }

    private static func runGit(root: URL, arguments: [String]) throws -> (status: Int32, text: String) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-workspace-git-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let output = try FileHandle(forWritingTo: outputURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        let input = try FileHandle(forReadingFrom: outputURL)
        defer { try? input.close() }
        let data = try input.read(upToCount: 180_001) ?? Data()
        let wasTruncated = data.count > 180_000
        var text = String(decoding: data.prefix(180_000), as: UTF8.self)
        if wasTruncated { text += "\n… Git output truncated at 180,000 bytes …" }
        return (process.terminationStatus, text)
    }
}
