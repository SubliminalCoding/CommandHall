import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class BrowserAddressTests: XCTestCase {
    func testAbsoluteURLsRemainUnchanged() {
        XCTAssertEqual(BrowserAddress.normalize("https://example.com/path"), "https://example.com/path")
        XCTAssertEqual(BrowserAddress.normalize("file:///tmp/index.html"), "file:///tmp/index.html")
    }

    func testHostNamesReceiveHTTPForLocalDevelopment() {
        XCTAssertEqual(BrowserAddress.normalize("localhost:8080"), "http://localhost:8080")
        XCTAssertEqual(BrowserAddress.normalize("127.0.0.1:3000"), "http://127.0.0.1:3000")
    }

    func testPrivateAndBonjourHostsReceiveHTTP() {
        XCTAssertEqual(BrowserAddress.normalize("192.168.1.50:8080"), "http://192.168.1.50:8080")
        XCTAssertEqual(BrowserAddress.normalize("10.0.0.4"), "http://10.0.0.4")
        XCTAssertEqual(BrowserAddress.normalize("172.16.5.9/status"), "http://172.16.5.9/status")
        XCTAssertEqual(BrowserAddress.normalize("spark.local"), "http://spark.local")
    }

    func testPublicDomainsDefaultToHTTPS() {
        // A bare public domain must become https:// — under App Transport
        // Security a cleartext http load to a remote host is blocked outright.
        XCTAssertEqual(BrowserAddress.normalize("youtube.com"), "https://youtube.com")
        XCTAssertEqual(BrowserAddress.normalize("github.com/anthropics"), "https://github.com/anthropics")
        XCTAssertEqual(BrowserAddress.normalize("news.ycombinator.com"), "https://news.ycombinator.com")
    }

    func testExplicitSchemesAreNeverRewritten() {
        XCTAssertEqual(BrowserAddress.normalize("http://example.com"), "http://example.com")
        XCTAssertEqual(BrowserAddress.normalize("https://example.com"), "https://example.com")
    }

    func testPlainTextBecomesSearchQuery() {
        XCTAssertEqual(BrowserAddress.normalize("native mac app"), "https://www.google.com/search?q=native%20mac%20app")
    }

    func testBraveDestinationUsesSearchForBlankPreview() {
        XCTAssertEqual(BraveBrowserSupport.destinationURL(for: nil), BraveBrowserSupport.blankPageURL)
        XCTAssertEqual(BraveBrowserSupport.destinationURL(for: "about:blank"), BraveBrowserSupport.blankPageURL)
    }

    func testBraveDestinationPreservesCurrentPage() {
        XCTAssertEqual(
            BraveBrowserSupport.destinationURL(for: "https://example.com/docs"),
            URL(string: "https://example.com/docs")
        )
    }

    func testBrowserRejectsLocalFileOutsideWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).html")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }

        let persistence = root.appendingPathComponent("state.json")
        let store = WorkspaceStore(persistenceURL: persistence)
        store.createWorkspace(name: "Boundary", rootPath: root.path)
        let browserID = store.createSession(provider: .browser, name: "Preview", purpose: "")
        let originalURL = store.activeWorkspace.nodes.first(where: { $0.id == browserID })?.url
        let escapedLink = root.appendingPathComponent("escaped.html")
        try FileManager.default.createSymbolicLink(at: escapedLink, withDestinationURL: outside)

        XCTAssertFalse(store.updateNodeURL(browserID, url: outside.absoluteString))
        XCTAssertFalse(store.updateNodeURL(browserID, url: escapedLink.absoluteString))
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == browserID })?.url, originalURL)
        XCTAssertTrue(store.supervisorMessage.contains("inside the current workspace"))
    }

    func testBrowserAllowsLocalFileInsideWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = root.appendingPathComponent("preview.html")
        try "inside".write(to: page, atomically: true, encoding: .utf8)

        let store = WorkspaceStore(persistenceURL: root.appendingPathComponent("state.json"))
        store.createWorkspace(name: "Boundary", rootPath: root.path)
        let browserID = store.createSession(provider: .browser, name: "Preview", purpose: "")

        XCTAssertTrue(store.updateNodeURL(browserID, url: page.absoluteString))
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == browserID })?.url, page.absoluteString)
    }
}
