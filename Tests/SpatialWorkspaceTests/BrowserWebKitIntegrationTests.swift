import SwiftUI
import WebKit
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class BrowserWebKitIntegrationTests: XCTestCase {
    func testEmbeddedBrowserAdvertisesCurrentSafariCompatibility() {
        let identity = BrowserRuntimeIdentity.applicationNameForUserAgent
        XCTAssertTrue(identity.contains("Version/"))
        XCTAssertTrue(identity.contains("Safari/605.1.15"))
    }

    func testFullscreenBridgeUsesContainedModeInsteadOfNativeWindowFullscreen() {
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("spatial-contained-fullscreen"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("document.querySelector('#movie_player')"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("youtube\\.com"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("html.spatial-youtube-cinema ytd-player"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("window.dispatchEvent(new Event('resize'))"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("window.__spatialEnterContainedFullscreen"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("window.__spatialExitContainedFullscreen"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("installMethod(Element.prototype, 'requestFullscreen'"))
        XCTAssertTrue(WebPreviewScripts.containedFullscreen.contains("installMethod(Document.prototype, 'exitFullscreen'"))
    }

    func testEmbeddedBrowserLoadsNewAddressWhenAddressAndRevisionChangeTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("<html><body>FIRST_PAGE</body></html>".utf8)
            .write(to: directory.appendingPathComponent("index.html"), options: .atomic)
        try Data("<html><body>SECOND_PAGE<a id='next' href='/third.html'></a></body></html>".utf8)
            .write(to: directory.appendingPathComponent("second.html"), options: .atomic)
        try Data("<html><body>THIRD_PAGE</body></html>".utf8)
            .write(to: directory.appendingPathComponent("third.html"), options: .atomic)

        let server = Process()
        let output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [
            "-u", "-c",
            "import http.server; s=http.server.ThreadingHTTPServer(('127.0.0.1',0),http.server.SimpleHTTPRequestHandler); print(s.server_address[1], flush=True); s.serve_forever()",
        ]
        server.currentDirectoryURL = directory
        server.standardOutput = output
        server.standardError = Pipe()
        try server.run()
        defer { if server.isRunning { server.terminate() } }

        let portData = output.fileHandleForReading.availableData
        let portText = String(decoding: portData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let port = try XCTUnwrap(Int(portText.split(separator: "\n")[0]))
        let model = BrowserHarnessModel(url: "http://127.0.0.1:\(port)/")
        let host = NSHostingView(rootView: BrowserHarness(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 720, height: 480)
        host.layoutSubtreeIfNeeded()

        let webView = try await waitForWebView(in: host)
        let loadedFirstPage = try await waitForBody("FIRST_PAGE", in: webView)
        XCTAssertTrue(loadedFirstPage)
        XCTAssertFalse(webView.configuration.preferences.isElementFullscreenEnabled)
        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertTrue(userAgent?.contains("Version/") == true)
        XCTAssertTrue(userAgent?.contains("Safari/605.1.15") == true)

        let fullscreenWasPatched = try await webView.evaluateJavaScript(
            "String(Element.prototype.requestFullscreen).includes('return enter(this)')"
        ) as? Bool
        XCTAssertEqual(fullscreenWasPatched, true)
        guard fullscreenWasPatched == true else { return }
        let enteredContainedFullscreen = try await webView.evaluateJavaScript(
            "(() => { void window.__spatialEnterContainedFullscreen(); return document.documentElement.classList.contains('spatial-contained-fullscreen') && document.fullscreenElement === document.documentElement; })()"
        ) as? Bool
        XCTAssertEqual(enteredContainedFullscreen, true)
        let exitedContainedFullscreen = try await webView.evaluateJavaScript(
            "(() => { void document.exitFullscreen(); return !document.body.classList.contains('spatial-contained-fullscreen') && document.fullscreenElement === null; })()"
        ) as? Bool
        XCTAssertEqual(exitedContainedFullscreen, true)

        model.navigate(to: "http://127.0.0.1:\(port)/second.html")

        let loadedSecondPage = try await waitForBody("SECOND_PAGE", in: webView)
        XCTAssertTrue(loadedSecondPage)
        XCTAssertEqual(webView.url?.lastPathComponent, "second.html")

        try await webView.evaluateJavaScript("document.getElementById('next').click()")

        let loadedLinkedPage = try await waitForBody("THIRD_PAGE", in: webView)
        XCTAssertTrue(loadedLinkedPage)
        XCTAssertEqual(webView.url?.lastPathComponent, "third.html")
    }

    func testLiveCNVSSiteLoadsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_BROWSER_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_BROWSER_E2E=1 to verify the public CNVS site")
        }
        let model = BrowserHarnessModel(url: "https://cnvs.dev")
        let host = NSHostingView(rootView: BrowserHarness(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 720, height: 480)
        host.layoutSubtreeIfNeeded()
        let webView = try await waitForWebView(in: host)

        let loaded = try await waitForNonemptyBody(in: webView, timeout: 15)

        XCTAssertTrue(loaded)
        XCTAssertTrue(webView.url?.host?.contains("cnvs.dev") == true)
    }

    func testLiveYouTubeCinemaKeepsVideoGeometryWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_YOUTUBE_E2E"] == "1",
              let url = ProcessInfo.processInfo.environment["RUN_REAL_YOUTUBE_URL"],
              !url.isEmpty else {
            throw XCTSkip("Set RUN_REAL_YOUTUBE_E2E=1 and RUN_REAL_YOUTUBE_URL to verify YouTube cinema mode")
        }
        let model = BrowserHarnessModel(url: url)
        let host = NSHostingView(rootView: BrowserHarness(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 960, height: 540)
        host.layoutSubtreeIfNeeded()
        let webView = try await waitForWebView(in: host)

        let foundPlayer = try await waitForJavaScriptTruth(
            "Boolean(document.querySelector('#movie_player') && document.querySelector('video'))",
            in: webView,
            timeout: 20
        )
        XCTAssertTrue(foundPlayer)
        guard foundPlayer else { return }

        _ = try await webView.evaluateJavaScript("void document.querySelector('#movie_player').requestFullscreen()")
        let geometryIsValid = try await waitForJavaScriptTruth(
            "(() => { const p=document.querySelector('ytd-player').getBoundingClientRect(); const v=document.querySelector('video').getBoundingClientRect(); return document.documentElement.classList.contains('spatial-youtube-cinema') && p.width >= innerWidth * 0.9 && p.height >= innerHeight * 0.9 && v.width > 0 && v.height > 0; })()",
            in: webView,
            timeout: 5
        )
        XCTAssertTrue(geometryIsValid)
    }

    private func waitForWebView(in root: NSView) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let webView = findWebView(in: root) { return webView }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "BrowserWebKitIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Embedded WKWebView was not created"])
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

    private func waitForNonemptyBody(in webView: WKWebView, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let body = try? await webView.evaluateJavaScript("document.body.innerText") as? String,
               !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func waitForJavaScriptTruth(_ script: String, in webView: WKWebView, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = try? await webView.evaluateJavaScript(script) as? Bool, result {
                return true
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }
}

@MainActor
private final class BrowserHarnessModel: ObservableObject {
    @Published var url: String
    @Published var revision = 0

    init(url: String) {
        self.url = url
    }

    func navigate(to nextURL: String) {
        url = nextURL
        revision += 1
    }
}

private struct BrowserHarness: View {
    @ObservedObject var model: BrowserHarnessModel
    @State private var state = WebPreviewState.idle

    var body: some View {
        WebPreview(urlString: model.url, revision: model.revision, state: $state)
    }
}
