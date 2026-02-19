//
//  ReadabilityExtractionService.swift
//  OpenRSS
//
//  Phase 3 — Content Extraction
//
//  Spins up a hidden WKWebView, navigates it to the article URL (so the
//  page's own JavaScript runs and renders dynamic content), waits for the
//  DOM to settle, then injects Mozilla Readability.js and extracts the
//  reader-mode content.
//
//  Why load the URL directly instead of a pre-fetched HTML string?
//  Single-page apps (e.g. RotoWire, ESPN, The Athletic) render their
//  content via JavaScript after the initial HTML arrives.  Loading a raw
//  HTML string prevents that JS from firing because there is no live network
//  connection.  Loading the URL gives the WebView a full browser context.
//
//  Settle delay: after didFinish we wait `jsSettleDelay` seconds before
//  running Readability, giving React/Vue/Angular time to paint the DOM.
//

import Foundation
import WebKit

// MARK: - Protocol

protocol ReadabilityExtractionServiceProtocol: Sendable {
    /// Navigates to `sourceURL` in a hidden WebView and extracts
    /// reader-mode content once the page has settled.
    @MainActor
    func extract(sourceURL: URL) async throws -> ReadableContent
}

// MARK: - Errors

enum ReadabilityError: LocalizedError {
    case readabilityJSNotFound
    case navigationFailed(Error)
    case javaScriptFailed(Error)
    case parseFailed(String)
    case noContent
    case timedOut

    var errorDescription: String? {
        switch self {
        case .readabilityJSNotFound:
            return "Readability.js was not found in the app bundle."
        case .navigationFailed(let e):
            return "WebView navigation failed: \(e.localizedDescription)"
        case .javaScriptFailed(let e):
            return "JavaScript evaluation failed: \(e.localizedDescription)"
        case .parseFailed(let msg):
            return "Readability.parse() failed: \(msg)"
        case .noContent:
            return "Readability could not extract readable content from this page."
        case .timedOut:
            return "The page took too long to load."
        }
    }
}

// MARK: - ReadabilityExtractionService

@MainActor
final class ReadabilityExtractionService: ReadabilityExtractionServiceProtocol {

    /// Seconds to wait after `didFinish` before running Readability,
    /// giving JavaScript-rendered content time to paint the DOM.
    private let jsSettleDelay: TimeInterval = 2.5

    /// Maximum total time before we give up and throw `.timedOut`.
    private let timeoutInterval: TimeInterval = 20

    // MARK: - Public API

    func extract(sourceURL: URL) async throws -> ReadableContent {
        guard let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let readabilityJS = try? String(contentsOf: jsURL, encoding: .utf8) else {
            throw ReadabilityError.readabilityJSNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = WebViewCoordinator(
                sourceURL:      sourceURL,
                readabilityJS:  readabilityJS,
                jsSettleDelay:  jsSettleDelay,
                timeoutInterval: timeoutInterval,
                continuation:   continuation
            )
            coordinator.start()
        }
    }
}

// MARK: - WebViewCoordinator

@MainActor
private final class WebViewCoordinator: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private let sourceURL:       URL
    private let readabilityJS:   String
    private let jsSettleDelay:   TimeInterval
    private let timeoutInterval: TimeInterval
    private var continuation:    CheckedContinuation<ReadableContent, Error>?
    private var hasFinished = false
    private var selfRetain: WebViewCoordinator?
    private var timeoutTask: DispatchWorkItem?

    init(
        sourceURL:       URL,
        readabilityJS:   String,
        jsSettleDelay:   TimeInterval,
        timeoutInterval: TimeInterval,
        continuation:    CheckedContinuation<ReadableContent, Error>
    ) {
        self.sourceURL       = sourceURL
        self.readabilityJS   = readabilityJS
        self.jsSettleDelay   = jsSettleDelay
        self.timeoutInterval = timeoutInterval
        self.continuation    = continuation
    }

    func start() {
        selfRetain = self

        // Give the WebView a realistic viewport so layout-dependent JS works.
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let wv = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: config
        )
        wv.navigationDelegate = self

        // Mobile user-agent so sites serve their standard layout
        wv.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.0 Mobile/15E148 Safari/604.1"

        webView = wv

        // Schedule a hard timeout
        let work = DispatchWorkItem { [weak self] in
            self?.finish(throwing: ReadabilityError.timedOut)
        }
        timeoutTask = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + timeoutInterval,
            execute: work
        )

        // Navigate to the real URL — the WebView fetches all resources and
        // runs the page's JavaScript exactly as Safari would.
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = timeoutInterval
        wv.load(request)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for JS frameworks to finish rendering the DOM before extracting.
        DispatchQueue.main.asyncAfter(deadline: .now() + jsSettleDelay) { [weak self] in
            self?.runReadability()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(throwing: ReadabilityError.navigationFailed(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(throwing: ReadabilityError.navigationFailed(error))
    }

    // MARK: - Readability Injection

    private func runReadability() {
        guard !hasFinished else { return }

        let script = """
        (function() {
            try {
                \(readabilityJS)
                var article = new Readability(document).parse();
                if (!article) {
                    return JSON.stringify({ error: "parse_returned_null" });
                }
                return JSON.stringify({
                    title:   article.title   || "",
                    byline:  article.byline  || null,
                    content: article.content || "",
                    excerpt: article.excerpt || null
                });
            } catch(e) {
                return JSON.stringify({ error: e.toString() });
            }
        })();
        """

        webView?.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, !self.hasFinished else { return }

            if let error {
                self.finish(throwing: ReadabilityError.javaScriptFailed(error))
                return
            }

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8) else {
                self.finish(throwing: ReadabilityError.noContent)
                return
            }

            self.decodeResult(data)
        }
    }

    // MARK: - JSON Decoding

    private func decodeResult(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                finish(throwing: ReadabilityError.noContent)
                return
            }

            if let errorMsg = json["error"] as? String {
                finish(throwing: ReadabilityError.parseFailed(errorMsg))
                return
            }

            let title   = (json["title"]   as? String) ?? ""
            let byline  =  json["byline"]  as? String
            let content = (json["content"] as? String) ?? ""
            let excerpt =  json["excerpt"] as? String

            let heroURL = extractHeroImageURL(from: content)

            finish(returning: ReadableContent(
                title:        title,
                byline:       byline,
                content:      content,
                excerpt:      excerpt,
                heroImageURL: heroURL
            ))
        } catch {
            finish(throwing: ReadabilityError.parseFailed(error.localizedDescription))
        }
    }

    // MARK: - Hero Image

    private func extractHeroImageURL(from html: String) -> URL? {
        guard let srcRange = html.range(of: "src=\"", options: .caseInsensitive) else { return nil }
        let afterSrc = html[srcRange.upperBound...]
        guard let endQuote = afterSrc.firstIndex(of: "\"") else { return nil }
        let urlString = String(afterSrc[..<endQuote])
        return URL(string: urlString)
    }

    // MARK: - Continuation Helpers

    private func finish(returning value: ReadableContent) {
        guard !hasFinished else { return }
        hasFinished = true
        tearDown()
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func finish(throwing error: Error) {
        guard !hasFinished else { return }
        hasFinished = true
        tearDown()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        selfRetain = nil
    }
}
