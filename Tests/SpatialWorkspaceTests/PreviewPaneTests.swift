import SwiftUI
import WebKit
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class PreviewPaneTests: XCTestCase {
    func testNormalizeConvertsAbsolutePathToFileURL() {
        let result = PreviewSource.normalize("/Users/someone/game/index.html")
        XCTAssertEqual(result, "file:///Users/someone/game/index.html")
    }

    func testNormalizeExpandsTildePaths() {
        let result = PreviewSource.normalize("~/game/index.html")
        XCTAssertTrue(result.hasPrefix("file://"))
        XCTAssertTrue(result.hasSuffix("/game/index.html"))
        XCTAssertFalse(result.contains("~"))
    }

    func testNormalizePassesThroughExplicitSchemes() {
        XCTAssertEqual(PreviewSource.normalize("file:///tmp/a.html"), "file:///tmp/a.html")
        XCTAssertEqual(PreviewSource.normalize("http://localhost:8777/index.html"), "http://localhost:8777/index.html")
        XCTAssertEqual(PreviewSource.normalize("https://example.com"), "https://example.com")
    }

    func testNormalizeTreatsLocalhostAsPlainHTTPDevServer() {
        XCTAssertEqual(PreviewSource.normalize("localhost:8777"), "http://localhost:8777")
    }

    func testNormalizeEmptyInputIsBlank() {
        XCTAssertEqual(PreviewSource.normalize("   "), "about:blank")
    }

    func testPreviewPaneLoadsLocalHTMLFileIntoEmbeddedWebView() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.html")
        try Data("<html><body>PREVIEW_OK</body></html>".utf8).write(to: file, options: .atomic)

        let model = PreviewHarnessModel(url: file.absoluteString)
        let host = NSHostingView(rootView: PreviewHarness(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        host.layoutSubtreeIfNeeded()

        let webView = try await waitForWebView(in: host)
        let loaded = try await waitForBody("PREVIEW_OK", in: webView)
        XCTAssertTrue(loaded, "PreviewPane should render the local HTML file")
    }

    private func waitForWebView(in root: NSView) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let webView = findWebView(in: root) { return webView }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "PreviewPaneTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Embedded WKWebView was not created"])
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        return view.subviews.lazy.compactMap(findWebView).first
    }

    private func waitForBody(_ expected: String, in webView: WKWebView) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let body = try? await webView.evaluateJavaScript("document.body.innerText") as? String,
               body == expected {
                return true
            }
            try await Task.sleep(nanoseconds: 75_000_000)
        }
        return false
    }
}

@MainActor
private final class PreviewHarnessModel: ObservableObject {
    @Published var url: String
    @Published var revision = 0

    init(url: String) {
        self.url = url
    }
}

private struct PreviewHarness: View {
    @ObservedObject var model: PreviewHarnessModel

    var body: some View {
        PreviewPane(
            node: WorkspaceNode(
                kind: .preview,
                title: "Preview",
                subtitle: "Preview",
                position: .zero,
                size: CGSize(width: 640, height: 400),
                zIndex: 0,
                url: model.url,
                revision: model.revision
            ),
            onNavigate: { model.url = $0 },
            onRefresh: { model.revision += 1 }
        )
    }
}
