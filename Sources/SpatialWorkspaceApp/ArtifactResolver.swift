import Foundation

struct ArtifactFileSnapshot: Equatable {
    var modifiedAt: Date
    var size: Int64
}

enum ArtifactResolver {
    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", "build", "DerivedData", "node_modules", ".next", "dist", "vendor",
    ]
    private static let artifactExtensions: Set<String> = [
        "html", "htm", "md", "markdown", "png", "jpg", "jpeg", "gif", "webp", "svg", "pdf",
        "txt", "json", "csv", "swift", "js", "jsx", "ts", "tsx", "css", "py", "rs", "go",
    ]

    static func snapshot(root: URL, limit: Int = 20_000) -> [String: ArtifactFileSnapshot] {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [:] }

        var result: [String: ArtifactFileSnapshot] = [:]
        for case let url as URL in enumerator {
            if result.count >= limit { break }
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard isWithin(resolvedURL, root: resolvedRoot) else { continue }
            let path = resolvedURL.path
            result[path] = ArtifactFileSnapshot(
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
        }
        return result
    }

    static func resolve(
        output: String,
        root: URL,
        before: [String: ArtifactFileSnapshot],
        after: [String: ArtifactFileSnapshot],
        allowFilesystemFallback: Bool = true
    ) -> [WorkspaceArtifact] {
        var candidates: [String: WorkspaceArtifact] = [:]

        for urlString in extractURLs(from: output) {
            candidates[urlString] = WorkspaceArtifact(
                kind: .url,
                title: URL(string: urlString)?.host ?? "Live preview",
                location: urlString,
                verified: false,
                modifiedAt: nil
            )
        }

        for path in extractPaths(from: output, root: root) {
            guard let artifact = fileArtifact(atPath: path, root: root) else { continue }
            candidates[artifact.location] = artifact
        }

        if allowFilesystemFallback {
            let changedPaths = after.compactMap { path, current -> String? in
                guard artifactExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { return nil }
                guard let previous = before[path] else { return path }
                return current != previous ? path : nil
            }
            for path in changedPaths {
                guard let artifact = fileArtifact(atPath: path, root: root) else { continue }
                candidates[artifact.location] = artifact
            }
        }

        return candidates.values
            .sorted { left, right in
                if left.kind.supportsEmbeddedPreview != right.kind.supportsEmbeddedPreview {
                    return left.kind.supportsEmbeddedPreview
                }
                let leftDate = left.modifiedAt ?? .distantPast
                let rightDate = right.modifiedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.location.localizedStandardCompare(right.location) == .orderedAscending
            }
            .prefix(12)
            .map { $0 }
    }

    static func primaryPreview(in artifacts: [WorkspaceArtifact]) -> WorkspaceArtifact? {
        if let localURL = artifacts.first(where: {
            guard $0.kind == .url, let host = URL(string: $0.location)?.host?.lowercased() else { return false }
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        }) {
            return localURL
        }
        let preference: [ArtifactKind] = [.html, .markdown, .image, .pdf, .text, .url]
        return preference.lazy.compactMap { kind in artifacts.first(where: { $0.kind == kind }) }.first
    }

    private static func fileArtifact(atPath path: String, root: URL) -> WorkspaceArtifact? {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard isWithin(url, root: resolvedRoot) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return WorkspaceArtifact(
            kind: kind(forExtension: url.pathExtension),
            title: url.lastPathComponent,
            location: url.path,
            verified: true,
            modifiedAt: values?.contentModificationDate
        )
    }

    private static func kind(forExtension pathExtension: String) -> ArtifactKind {
        switch pathExtension.lowercased() {
        case "html", "htm": .html
        case "md", "markdown": .markdown
        case "png", "jpg", "jpeg", "gif", "webp", "svg": .image
        case "pdf": .pdf
        case "txt", "json", "csv": .text
        default: .file
        }
    }

    private static func extractURLs(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        }
    }

    private static func extractPaths(from text: String, root: URL) -> [String] {
        let pattern = #"(?:/[^\s\"'`<>]+|(?:\.?\.?/)?[A-Za-z0-9_@+,. -]+\.(?:html?|md|markdown|png|jpe?g|gif|webp|svg|pdf|txt|json|csv|swift|jsx?|tsx?|css|py|rs|go))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        return expression.matches(in: text, range: range).compactMap { result -> String? in
            guard let matchRange = Range(result.range, in: text) else { return nil }
            var candidate = String(text[matchRange])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "`'\".,;:!?()[]{}")))
            while candidate.hasPrefix("./") { candidate.removeFirst(2) }
            let url = candidate.hasPrefix("/")
                ? URL(fileURLWithPath: candidate)
                : root.appendingPathComponent(candidate)
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard isWithin(resolvedURL, root: resolvedRoot) else { return nil }
            return resolvedURL.path
        }
    }

    private static func isWithin(_ file: URL, root: URL) -> Bool {
        file.path == root.path || file.path.hasPrefix(root.path + "/")
    }
}
