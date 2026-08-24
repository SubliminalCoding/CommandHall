import AppKit
import SwiftUI
import WebKit

enum BrowserRuntimeIdentity {
    static var applicationNameForUserAgent: String {
        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let version = (Bundle(url: safariURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .split(separator: ".")
            .prefix(2)
            .joined(separator: ".")
        return "Version/\((version?.isEmpty == false ? version : nil) ?? "18.0") Safari/605.1.15"
    }
}

enum WebPreviewScripts {
    static let fullscreenMessageName = "spatialFullscreen"
    static let containedFullscreen = #"""
    (() => {
      if (window.__spatialContainedFullscreenInstalled) return;
      window.__spatialContainedFullscreenInstalled = true;
      const message = (active) => {
        try { window.webkit.messageHandlers.spatialFullscreen.postMessage(active); } catch (_) {}
      };
      const style = document.createElement('style');
      style.id = 'spatial-contained-fullscreen-style';
      style.textContent = `
        .spatial-contained-fullscreen {
          position: fixed !important; inset: 0 !important; z-index: 2147483647 !important;
          width: 100vw !important; height: 100vh !important; max-width: none !important;
          max-height: none !important; margin: 0 !important; background: #000 !important;
        }
        html.spatial-youtube-cinema,
        html.spatial-youtube-cinema body {
          overflow: hidden !important; background: #000 !important;
        }
        html.spatial-youtube-cinema ytd-masthead,
        html.spatial-youtube-cinema #masthead-container,
        html.spatial-youtube-cinema #guide,
        html.spatial-youtube-cinema #secondary,
        html.spatial-youtube-cinema #below,
        html.spatial-youtube-cinema #chat-container,
        html.spatial-youtube-cinema ytd-live-chat-frame {
          visibility: hidden !important;
        }
        html.spatial-youtube-cinema ytd-player {
          position: fixed !important; inset: 0 !important; z-index: 2147483647 !important;
          display: block !important; width: 100vw !important; height: 100vh !important;
          max-width: none !important; max-height: none !important; margin: 0 !important;
          background: #000 !important;
        }
        html.spatial-youtube-cinema #movie_player {
          width: 100% !important; height: 100% !important;
        }
        body.spatial-fullscreen-active { overflow: hidden !important; }
      `;
      (document.head || document.documentElement).appendChild(style);
      let activeElement = null;
      let youtubeCinema = false;
      const notifyResize = () => {
        requestAnimationFrame(() => requestAnimationFrame(() => {
          window.dispatchEvent(new Event('resize'));
        }));
      };
      const enter = (element) => {
        if (!element) return Promise.reject(new TypeError('No fullscreen element'));
        const isYouTube = /(^|\.)youtube\.com$/.test(location.hostname);
        const youtubePlayer = isYouTube
          ? (document.querySelector('#movie_player') || document.querySelector('video')?.closest('.html5-video-player'))
          : null;
        if (activeElement) activeElement.classList.remove('spatial-contained-fullscreen');
        document.documentElement.classList.remove('spatial-youtube-cinema');
        youtubeCinema = Boolean(youtubePlayer);
        activeElement = youtubePlayer || element;
        if (youtubeCinema) {
          document.documentElement.classList.add('spatial-youtube-cinema');
        } else {
          activeElement.classList.add('spatial-contained-fullscreen');
        }
        document.body?.classList.add('spatial-fullscreen-active');
        document.dispatchEvent(new Event('fullscreenchange'));
        notifyResize();
        message(true);
        return Promise.resolve();
      };
      const exit = () => {
        activeElement?.classList.remove('spatial-contained-fullscreen');
        document.documentElement.classList.remove('spatial-youtube-cinema');
        activeElement = null;
        youtubeCinema = false;
        document.body?.classList.remove('spatial-fullscreen-active');
        document.dispatchEvent(new Event('fullscreenchange'));
        notifyResize();
        message(false);
        return Promise.resolve();
      };
      window.__spatialEnterContainedFullscreen = () => {
        const target = document.querySelector('#movie_player')
          || document.querySelector('video')
          || document.documentElement;
        return enter(target);
      };
      window.__spatialExitContainedFullscreen = exit;
      const installMethod = (target, name, value) => {
        try { Object.defineProperty(target, name, { configurable: true, writable: true, value }); }
        catch (_) { try { target[name] = value; } catch (_) {} }
      };
      try { Object.defineProperty(Document.prototype, 'fullscreenElement', { configurable: true, get: () => activeElement }); } catch (_) {}
      try { Object.defineProperty(Document.prototype, 'webkitFullscreenElement', { configurable: true, get: () => activeElement }); } catch (_) {}
      try { Object.defineProperty(Document.prototype, 'fullscreenEnabled', { configurable: true, get: () => true }); } catch (_) {}
      installMethod(Element.prototype, 'requestFullscreen', function() { return enter(this); });
      installMethod(Element.prototype, 'webkitRequestFullscreen', function() { return enter(this); });
      installMethod(Document.prototype, 'exitFullscreen', exit);
      installMethod(Document.prototype, 'webkitExitFullscreen', exit);
      document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && activeElement) { event.preventDefault(); void exit(); }
      }, true);
      window.addEventListener('pagehide', () => message(false));
    })();
    """#
}

struct WebPreviewState: Equatable {
    var currentURL: String?
    var title: String?
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var estimatedProgress = 0.0
    var errorMessage: String?

    static let idle = WebPreviewState()
}

enum WebPreviewAction: Equatable {
    case back
    case forward
    case reload
    case stop
    case navigate(String)
    case enterContainedFullscreen
    case exitContainedFullscreen
}

struct WebPreviewCommand: Equatable {
    let id = UUID()
    let action: WebPreviewAction
}

struct WebPreview: NSViewRepresentable {
    let urlString: String
    let revision: Int
    @Binding private var state: WebPreviewState
    @Binding private var isContainedFullscreen: Bool
    private let pageZoom: Double
    private let command: WebPreviewCommand?
    private let initialJavaScript: String?
    private let allowsLoopbackMediaCapture: Bool

    init(
        urlString: String,
        revision: Int,
        state: Binding<WebPreviewState> = .constant(.idle),
        isContainedFullscreen: Binding<Bool> = .constant(false),
        pageZoom: Double = 1,
        command: WebPreviewCommand? = nil,
        initialJavaScript: String? = nil,
        allowsLoopbackMediaCapture: Bool = false
    ) {
        self.urlString = urlString
        self.revision = revision
        _state = state
        _isContainedFullscreen = isContainedFullscreen
        self.pageZoom = pageZoom
        self.command = command
        self.initialJavaScript = initialJavaScript
        self.allowsLoopbackMediaCapture = allowsLoopbackMediaCapture
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = BrowserRuntimeIdentity.applicationNameForUserAgent
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebPreviewScripts.containedFullscreen,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.add(
            context.coordinator,
            name: WebPreviewScripts.fullscreenMessageName
        )

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsMagnification = true
        view.pageZoom = pageZoom

        context.coordinator.webView = view
        context.coordinator.lastRequestedURL = urlString
        context.coordinator.lastRevision = revision
        context.coordinator.initialJavaScript = initialJavaScript
        context.coordinator.allowsLoopbackMediaCapture = allowsLoopbackMediaCapture
        context.coordinator.onContainedFullscreenChange = { isContainedFullscreen = $0 }
        context.coordinator.publishState()
        load(urlString, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onStateChange = { nextState in
            if state != nextState { state = nextState }
        }
        if abs(view.pageZoom - pageZoom) > 0.001 { view.pageZoom = pageZoom }
        context.coordinator.initialJavaScript = initialJavaScript
        context.coordinator.allowsLoopbackMediaCapture = allowsLoopbackMediaCapture
        context.coordinator.onContainedFullscreenChange = { active in
            if isContainedFullscreen != active { isContainedFullscreen = active }
        }

        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            switch command.action {
            case .back: view.goBack()
            case .forward: view.goForward()
            case .reload: view.reload()
            case .stop: view.stopLoading()
            case let .navigate(destination):
                load(destination, in: view)
            case .enterContainedFullscreen:
                view.evaluateJavaScript("window.__spatialEnterContainedFullscreen?.()")
            case .exitContainedFullscreen:
                view.evaluateJavaScript("window.__spatialExitContainedFullscreen?.() ?? document.exitFullscreen?.()")
            }
        }

        if context.coordinator.lastRequestedURL != urlString {
            context.coordinator.lastRequestedURL = urlString
            context.coordinator.lastRevision = revision
            load(urlString, in: view)
            return
        }
        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            view.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator { nextState in
            if state != nextState { state = nextState }
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: WebPreviewScripts.fullscreenMessageName)
        coordinator.webView = nil
    }

    private func load(_ value: String, in view: WKWebView) {
        guard let url = URL(string: value) else {
            state.errorMessage = "That address is not valid."
            return
        }
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastRequestedURL: String?
        var lastRevision = 0
        var lastCommandID: UUID?
        var onStateChange: (WebPreviewState) -> Void
        var initialJavaScript: String?
        var allowsLoopbackMediaCapture = false
        var onContainedFullscreenChange: (Bool) -> Void = { _ in }

        init(onStateChange: @escaping (WebPreviewState) -> Void) {
            self.onStateChange = onStateChange
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onContainedFullscreenChange(false)
            publishState(isLoading: true, errorMessage: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == WebPreviewScripts.fullscreenMessageName,
                  let active = message.body as? Bool else { return }
            onContainedFullscreenChange(active)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publishState(isLoading: true, errorMessage: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publishState(isLoading: false, errorMessage: nil)
            if let initialJavaScript {
                webView.evaluateJavaScript(initialJavaScript)
            }
        }

        @available(macOS 12.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let trustedHosts = ["127.0.0.1", "localhost", "::1"]
            let isTrustedLoopback = trustedHosts.contains(origin.host.lowercased())
            decisionHandler(allowsLoopbackMediaCapture && isTrustedLoopback ? .grant : .deny)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publishFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publishFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let supportedSchemes = ["about", "file", "http", "https"]
            guard supportedSchemes.contains(url.scheme?.lowercased() ?? "") else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let request = navigationAction.request.url {
                webView.load(URLRequest(url: request))
            }
            return nil
        }

        func publishState(isLoading: Bool? = nil, errorMessage: String? = nil) {
            guard let webView else { return }
            onStateChange(
                WebPreviewState(
                    currentURL: webView.url?.absoluteString,
                    title: webView.title,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward,
                    isLoading: isLoading ?? webView.isLoading,
                    estimatedProgress: webView.estimatedProgress,
                    errorMessage: errorMessage
                )
            )
        }

        private func publishFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            publishState(isLoading: false, errorMessage: nsError.localizedDescription)
        }
    }
}
