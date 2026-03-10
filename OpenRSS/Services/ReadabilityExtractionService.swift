//
//  ReadabilityExtractionService.swift
//  OpenRSS
//
//  Phase 3 — Content Extraction
//
//  Acquires a pre-warmed WKWebView from WebViewPool (Readability.js is
//  already injected), navigates it to the article URL, waits for the DOM
//  to settle, then runs Readability.parse() and returns ReadableContent.
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
        // Acquire a pre-warmed WKWebView from the pool.
        // Readability.js is already injected as a user script.
        let webView = await WebViewPool.shared.acquire()

        do {
            let result = try await performExtraction(webView: webView, sourceURL: sourceURL)
            WebViewPool.shared.returnToPool(webView)
            return result
        } catch {
            WebViewPool.shared.returnToPool(webView)
            throw error
        }
    }

    // MARK: - Extraction

    private func performExtraction(webView: WKWebView, sourceURL: URL) async throws -> ReadableContent {
        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = WebViewCoordinator(
                webView:         webView,
                sourceURL:       sourceURL,
                jsSettleDelay:   jsSettleDelay,
                timeoutInterval: timeoutInterval,
                continuation:    continuation
            )
            coordinator.start()
        }
    }
}

// MARK: - WebViewCoordinator

@MainActor
private final class WebViewCoordinator: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private let sourceURL:       URL
    private let jsSettleDelay:   TimeInterval
    private let timeoutInterval: TimeInterval
    private var continuation:    CheckedContinuation<ReadableContent, Error>?
    private var hasFinished = false
    private var selfRetain: WebViewCoordinator?
    private var timeoutTask: DispatchWorkItem?

    init(
        webView:         WKWebView,
        sourceURL:       URL,
        jsSettleDelay:   TimeInterval,
        timeoutInterval: TimeInterval,
        continuation:    CheckedContinuation<ReadableContent, Error>
    ) {
        self.webView         = webView
        self.sourceURL       = sourceURL
        self.jsSettleDelay   = jsSettleDelay
        self.timeoutInterval = timeoutInterval
        self.continuation    = continuation
    }

    func cancel() {
        finish(throwing: CancellationError())
    }

    func start() {
        selfRetain = self

        webView.navigationDelegate = self

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
        webView.load(request)
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

        // Readability.js is already injected as a user script via WebViewPool.
        // We only need to invoke it here.
        let script = """
        (function() {
            try {
                var ogEl = document.querySelector('meta[property="og:image"]')
                        || document.querySelector('meta[name="og:image"]');
                var ogImage = ogEl ? (ogEl.getAttribute('content') || null) : null;

                var article = new Readability(document).parse();
                if (!article) {
                    return JSON.stringify({ error: "parse_returned_null" });
                }
                return JSON.stringify({
                    title:   article.title   || "",
                    byline:  article.byline  || null,
                    content: article.content || "",
                    excerpt: article.excerpt || null,
                    ogImage: ogImage
                });
            } catch(e) {
                return JSON.stringify({ error: e.toString() });
            }
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
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

            let ogImageURL = (json["ogImage"] as? String).flatMap { URL(string: $0) }
            let heroURL = ogImageURL ?? extractHeroImageURL(from: content)

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
        guard let imgTagRegex = try? NSRegularExpression(
                  pattern: #"<img\b([^>]*)>"#, options: .caseInsensitive),
              let srcRegex = try? NSRegularExpression(
                  pattern: #"\bsrc=["']([^"']+)["']"#, options: .caseInsensitive),
              let dimRegex = try? NSRegularExpression(
                  pattern: #"\b(?:width|height)=["']?(\d+)["']?"#, options: .caseInsensitive)
        else { return nil }

        let nsRange = NSRange(html.startIndex..., in: html)
        for match in imgTagRegex.matches(in: html, range: nsRange) {
            guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
            let attrs = String(html[attrRange])
            let attrNS = NSRange(attrs.startIndex..., in: attrs)

            guard let srcMatch = srcRegex.firstMatch(in: attrs, range: attrNS),
                  let srcRange = Range(srcMatch.range(at: 1), in: attrs)
            else { continue }

            let candidate = String(attrs[srcRange])
            guard candidate.hasPrefix("https://") else { continue }

            var isTiny = false
            for dimMatch in dimRegex.matches(in: attrs, range: attrNS) {
                if let valRange = Range(dimMatch.range(at: 1), in: attrs),
                   let val = Int(attrs[valRange]), val < 100 {
                    isTiny = true
                    break
                }
            }
            if isTiny { continue }

            return URL(string: candidate)
        }
        return nil
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
        webView.navigationDelegate = nil
        webView.stopLoading()
        // Do NOT nil out webView — it's owned by the pool and will be returned.
        selfRetain = nil
    }
}
