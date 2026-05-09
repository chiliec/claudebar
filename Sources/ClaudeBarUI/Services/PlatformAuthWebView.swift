import SwiftUI
import WebKit

@MainActor
public struct PlatformAuthWebView: NSViewRepresentable {
    public let onCapture: (String) -> Void
    public let onCancel: () -> Void

    public init(onCapture: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Isolated, non-persistent data store: fresh login every time, no Safari pollution.
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://platform.claude.com/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Pure cookie-filter predicate. Exposed for unit testing — `WKWebView`
    /// itself is impractical to instantiate from the test target.
    public static func extractPlatformSessionKey(from cookies: [HTTPCookie]) -> String? {
        cookies.first { cookie in
            cookie.name == "sessionKey" && cookie.domain == "platform.claude.com"
        }?.value
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PlatformAuthWebView
        private var captured = false

        init(parent: PlatformAuthWebView) {
            self.parent = parent
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !captured else { return }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                guard let value = PlatformAuthWebView.extractPlatformSessionKey(from: cookies) else { return }
                self.captured = true
                Task { @MainActor in self.parent.onCapture(value) }
            }
        }
    }
}
