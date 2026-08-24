import XCTest
@testable import SpatialWorkspaceApp

final class ArtifactResolverTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testChangedHTMLBecomesVerifiedPreviewArtifact() throws {
        let root = try temporaryDirectory()
        let before = ArtifactResolver.snapshot(root: root)
        let file = root.appendingPathComponent("snake.html")
        try Data("<html><body>Snake</body></html>".utf8).write(to: file)

        let artifacts = ArtifactResolver.resolve(
            output: "Created snake.html",
            root: root,
            before: before,
            after: ArtifactResolver.snapshot(root: root)
        )

        let artifact = try XCTUnwrap(artifacts.first(where: { $0.title == "snake.html" }))
        XCTAssertEqual(artifact.kind, .html)
        XCTAssertEqual(artifact.location, file.path)
        XCTAssertEqual(artifact.previewURL, file.absoluteString)
        XCTAssertTrue(artifact.verified)
    }

    func testPathsOutsideWorkspaceAreIgnored() throws {
        let root = try temporaryDirectory()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).html")
        try Data("outside".utf8).write(to: outside)

        let artifacts = ArtifactResolver.resolve(output: outside.path, root: root, before: [:], after: [:])

        XCTAssertFalse(artifacts.contains(where: { $0.location == outside.path }))
    }

    func testSymlinkToFileOutsideWorkspaceIsIgnored() throws {
        let root = try temporaryDirectory()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).html")
        try Data("outside".utf8).write(to: outside)
        let link = root.appendingPathComponent("linked.html")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let artifacts = ArtifactResolver.resolve(output: link.path, root: root, before: [:], after: [:])

        XCTAssertTrue(artifacts.isEmpty)
    }

    func testLiveLocalURLIsPreferredForPreview() throws {
        let root = try temporaryDirectory()
        let artifacts = ArtifactResolver.resolve(
            output: "Server ready at http://127.0.0.1:4173",
            root: root,
            before: [:],
            after: [:]
        )

        XCTAssertEqual(ArtifactResolver.primaryPreview(in: artifacts)?.location, "http://127.0.0.1:4173")
    }

    func testFilesystemFallbackCanBeDisabledForConversationalRuns() throws {
        let root = try temporaryDirectory()
        let before = ArtifactResolver.snapshot(root: root)
        let unrelated = root.appendingPathComponent("unrelated.html")
        try Data("unrelated".utf8).write(to: unrelated)

        let artifacts = ArtifactResolver.resolve(
            output: "Okay, understood.",
            root: root,
            before: before,
            after: ArtifactResolver.snapshot(root: root),
            allowFilesystemFallback: false
        )

        XCTAssertTrue(artifacts.isEmpty)
    }
}
