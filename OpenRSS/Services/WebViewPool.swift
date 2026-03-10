//
//  WebViewPool.swift
//  OpenRSS
//
//  Priority 1 — WKWebView Warm Pool
//
//  Pre-initializes a pool of WKWebView instances at app launch with
//  Readability.js already injected as a user script.  Eliminates the
//  ~800ms–1.5s cold-start overhead that comes from creating a new
//  WKWebView + loading 89KB of JS for every single article open.
//
//  Usage:
//    WebViewPool.shared.warmUp()          // call once at app launch
//    let wv = await WebViewPool.shared.acquire()   // get a warm view
//    await WebViewPool.shared.returnToPool(wv)     // hand it back
//

import WebKit

@MainActor
final class WebViewPool {

    static let shared = WebViewPool()

    // MARK: - Configuration

    private let poolSize = 2

    // MARK: - State

    private var available: [WKWebView] = []
    private var waiters: [CheckedContinuation<WKWebView, Never>] = []

    // MARK: - Shared Configuration

    /// A single WKWebViewConfiguration shared by every pooled view.
    /// Readability.js is injected once here — never loaded per-article again.
    private lazy var sharedConfig: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        if let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(
                source: jsSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }

        return config
    }()

    // MARK: - Warm Up

    /// Call at app launch to pre-create pooled WKWebViews.
    /// Non-blocking — fires and forgets on the main actor.
    func warmUp() {
        for _ in 0..<poolSize {
            let wv = makeWebView()
            available.append(wv)
        }
    }

    // MARK: - Acquire / Return

    /// Acquire a ready-to-use WKWebView with Readability.js pre-injected.
    /// Waits if none are currently available.
    func acquire() async -> WKWebView {
        if let webView = available.first {
            available.removeFirst()
            return webView
        }

        // All views are in use — wait for one to come back.
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Return a WKWebView to the pool after use.
    /// Resets the view by loading about:blank so it's clean for the next caller.
    func returnToPool(_ webView: WKWebView) {
        // Reset state for next use
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.load(URLRequest(url: URL(string: "about:blank")!))

        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: webView)
        } else if available.count < poolSize {
            available.append(webView)
        }
        // If pool is full, let the extra view deallocate
    }

    // MARK: - Private

    private func makeWebView() -> WKWebView {
        let wv = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: sharedConfig
        )
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.0 Mobile/15E148 Safari/604.1"
        return wv
    }
}
