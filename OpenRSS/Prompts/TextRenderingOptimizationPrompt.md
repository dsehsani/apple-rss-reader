# Text Rendering Pipeline Optimization Prompt
**OpenRSS — Target: Reduce ~6s pipeline to <2s perceived load time**

---

## Context for Claude

This is the **OpenRSS** iOS SwiftUI app. When a user taps an article, the text rendering pipeline currently takes ~6 seconds before content is visible. The pipeline runs entirely on-device.

The key files involved are:

| File | Size | Role |
|---|---|---|
| `ReadabilityExtractionService.swift` | ~12KB | Runs Mozilla Readability.js via WKWebView to extract article content |
| `ContentFetcherService.swift` | ~4KB | Fetches raw HTML from the article URL |
| `ArticlePipelineService.swift` | ~3.5KB | Orchestrates the full extraction pipeline |
| `ContentNormalizerService.swift` | ~9KB | Normalizes extracted HTML into ContentNodes |
| `Readability.js` | 89KB | Mozilla's Readability library (injected into WKWebView) |
| `ArticleReaderView.swift` | — | Renders ContentNodes as SwiftUI views |
| `ArticleReaderHostView.swift` | — | Host view for the article reader |
| `ParagraphView.swift` | — | Renders paragraph nodes |
| `HeadingView.swift` | — | Renders heading nodes (h1/h2/h3) |
| `BlockquoteView.swift` | — | Renders blockquote nodes |
| `CodeBlockView.swift` | — | Renders code block nodes |
| `TableView.swift` | — | Renders table nodes |
| `ListItemsView.swift` | — | Renders ordered/unordered list nodes |
| `ArticleImageView.swift` | — | Renders image nodes |
| `ContentNode.swift` | — | The ContentNode model enum |
| `ArticleCacheService.swift` | ~4.5KB | Article caching service |
| `ArticleCacheStore.swift` | ~2.7KB | Cache store implementation |

---

## Current Pipeline (Sequential — ~6 seconds)

```
User taps article
       ↓
1. ContentFetcherService:  fetchHTML(url)           ~1.5s  [network]
       ↓
2. ReadabilityExtractionService:                    ~2.5s  [WKWebView cold start + JS]
   - Create new WKWebView
   - Load Readability.js (89KB)
   - Load HTML into WKWebView
   - evaluateJavaScript: new Readability(document).parse()
   - Decode JSON result
       ↓
3. ContentNormalizerService: parseToContentNodes()  ~0.8s  [HTML → ContentNode tree]
       ↓
4. ArticleReaderView renders ContentNodes           ~0.5s  [SwiftUI layout]
       ↓
User sees content                                  TOTAL: ~6.0s
```

---

## Optimization Goals

Please implement the following optimizations **in priority order**. Each section is self-contained and can be implemented independently.

---

## Priority 1 — WKWebView Warm Pool (Saves ~1.5s)

**Problem:** A new `WKWebView` is created for each article, causing ~800ms–1.5s cold-start overhead every time.

**Solution:** Pre-initialize a pool of 2–3 `WKWebView` instances at app launch with `Readability.js` already injected. Reuse them across article extractions.

**Implementation:**

Create a new file `WebViewPool.swift` in the Services folder:

```swift
import WebKit

/// A pool of pre-warmed WKWebView instances with Readability.js pre-injected.
/// Eliminates ~1.5s cold-start penalty per article extraction.
actor WebViewPool {
    static let shared = WebViewPool()

    private let poolSize = 2
    private var available: [WKWebView] = []
    private var waiters: [CheckedContinuation<WKWebView, Never>] = []

    private let sharedConfig: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        // Single shared process pool reduces memory overhead
        config.processPool = WKProcessPool()

        // Pre-inject Readability.js ONCE — never load it per-article again
        if let jsURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(
                source: jsSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }
        return config
    }()

    /// Call this at app launch (e.g., in OpenRSSApp.init or AppState.init).
    nonisolated func warmUp() {
        Task {
            for _ in 0..<poolSize {
                let webView = await makeWebView()
                await returnToPool(webView)
            }
        }
    }

    /// Acquire a ready-to-use WKWebView. Waits if none available.
    func acquire() async -> WKWebView {
        if let webView = available.first {
            available.removeFirst()
            return webView
        }
        // Wait for one to become available
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Return a WKWebView to the pool after use.
    func returnToPool(_ webView: WKWebView) {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: webView)
        } else if available.count < poolSize {
            available.append(webView)
        }
        // If pool is full, discard — don't let it grow unbounded
    }

    @MainActor
    private func makeWebView() -> WKWebView {
        WKWebView(frame: .zero, configuration: sharedConfig)
    }
}
```

**Wire it up in `OpenRSSApp.swift` or `AppState.swift`:**
```swift
init() {
    // Pre-warm WKWebView pool at app launch (async, no blocking)
    WebViewPool.shared.warmUp()
    // ... rest of init
}
```

**Update `ReadabilityExtractionService.swift`** to use the pool instead of creating new instances:
```swift
// BEFORE:
let webView = WKWebView(frame: .zero, configuration: config)
// load Readability.js again...

// AFTER:
let webView = await WebViewPool.shared.acquire()
defer { Task { await WebViewPool.shared.returnToPool(webView) } }
// Readability.js is already injected — skip that step entirely
```

---

## Priority 2 — Parallel Network Fetch + WKWebView Acquisition (Saves ~1.0–1.5s)

**Problem:** The pipeline fetches HTML *then* acquires a WKWebView sequentially. Both can happen simultaneously.

**Solution:** Use Swift `async let` to start both operations in parallel. This turns the longest two sequential steps into a single parallel wait equal to `max(networkTime, webViewAcquisitionTime)`.

**Update `ArticlePipelineService.swift`:**
```swift
func loadArticle(url: URL) async throws -> [ContentNode] {
    // ✅ Start BOTH operations in parallel
    async let htmlFetch   = ContentFetcherService.shared.fetchHTML(from: url)
    async let webView     = WebViewPool.shared.acquire()

    // Wait for both to complete (total = max of the two, not sum)
    let html      = try await htmlFetch
    let readyView = await webView

    defer { Task { await WebViewPool.shared.returnToPool(readyView) } }

    // Now extract — WKWebView is already warm, Readability.js already loaded
    let extracted = try await ReadabilityExtractionService.shared
        .extract(html: html, using: readyView, sourceURL: url)

    let nodes = ContentNormalizerService.shared.normalize(extracted)
    return nodes
}
```

---

## Priority 3 — Multi-Layer Article Cache (Repeat opens: ~6s → <0.1s)

**Problem:** Every article open re-fetches and re-extracts, even if the user opened the same article moments ago.

**Solution:** Cache the parsed `[ContentNode]` tree in a two-level cache (memory + disk). Memory cache is instant; disk cache survives app relaunch.

**Update `ArticleCacheService.swift`:**
```swift
import Foundation

final class ArticleCacheService {
    static let shared = ArticleCacheService()

    // MARK: - Memory Cache (instant, survives session)
    private let memCache = NSCache<NSString, NSData>()

    // MARK: - Disk Cache (persistent, survives relaunch)
    private let diskDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArticleNodes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let maxDiskAgeDays: Double = 7

    init() {
        memCache.totalCostLimit = 30 * 1024 * 1024  // 30 MB
        memCache.countLimit = 50
    }

    // MARK: - Read (memory → disk → nil)
    func cachedNodes(for url: String) -> [ContentNode]? {
        let key = cacheKey(for: url)

        // 1. Memory hit — instant
        if let data = memCache.object(forKey: key as NSString) as Data? {
            return try? JSONDecoder().decode([ContentNode].self, from: data)
        }

        // 2. Disk hit — fast, promote to memory
        let fileURL = diskDir.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxDiskAgeDays * 86400,
              let data = try? Data(contentsOf: fileURL),
              let nodes = try? JSONDecoder().decode([ContentNode].self, from: data)
        else { return nil }

        // Promote to memory for next access
        memCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return nodes
    }

    // MARK: - Write (both layers, async disk write)
    func cache(_ nodes: [ContentNode], for url: String) {
        guard let data = try? JSONEncoder().encode(nodes) else { return }
        let key = cacheKey(for: url)

        // Write to memory immediately
        memCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)

        // Write to disk async (don't block pipeline)
        let fileURL = diskDir.appendingPathComponent(key)
        Task(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Clear stale entries
    func pruneExpiredEntries() {
        Task(priority: .background) {
            let cutoff = Date().addingTimeInterval(-self.maxDiskAgeDays * 86400)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: self.diskDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            for file in files {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private func cacheKey(for url: String) -> String {
        // Stable filename-safe hash
        String(format: "%08x", url.hashValue & 0xFFFFFFFF)
    }
}
```

**Integrate cache at the pipeline entry point in `ArticlePipelineService.swift`:**
```swift
func loadArticle(url: URL) async throws -> [ContentNode] {
    let cacheKey = url.absoluteString

    // ✅ Check cache FIRST — instant return if available
    if let cached = ArticleCacheService.shared.cachedNodes(for: cacheKey) {
        return cached
    }

    // Full pipeline (parallel fetch + webview)
    async let htmlFetch = ContentFetcherService.shared.fetchHTML(from: url)
    async let webView   = WebViewPool.shared.acquire()

    let html      = try await htmlFetch
    let readyView = await webView
    defer { Task { await WebViewPool.shared.returnToPool(readyView) } }

    let extracted = try await ReadabilityExtractionService.shared
        .extract(html: html, using: readyView, sourceURL: url)
    let nodes = ContentNormalizerService.shared.normalize(extracted)

    // ✅ Cache result for next time (async, non-blocking)
    ArticleCacheService.shared.cache(nodes, for: cacheKey)

    return nodes
}
```

---

## Priority 4 — Background Pre-Fetching (Perceived load: near-instant)

**Problem:** Users see the 6-second wait *after* tapping. Pre-extraction while browsing the list makes the detail view open instantly.

**Solution:** When the article list loads, silently pre-fetch and pre-extract the top articles in the background at low priority. By the time the user taps, content is already cached.

**Add to the ViewModel that manages the article list (e.g., `TodayViewModel.swift` or `MyFeedsViewModel.swift`):**
```swift
private var prefetchTask: Task<Void, Never>?

/// Call this after the article list is loaded.
func startPrefetching(_ articles: [Article]) {
    prefetchTask?.cancel()
    prefetchTask = Task(priority: .utility) {
        // Pre-fetch top 5 articles in the background
        for article in articles.prefix(5) {
            guard !Task.isCancelled else { return }

            // Skip if already cached
            guard ArticleCacheService.shared.cachedNodes(for: article.url.absoluteString) == nil else {
                continue
            }

            // Only prefetch if memory is available
            if isUnderMemoryPressure() { return }

            do {
                let nodes = try await ArticlePipelineService.shared.loadArticle(url: article.url)
                // loadArticle automatically caches — nothing else needed
                _ = nodes
            } catch {
                // Non-critical: silent failure is fine for prefetch
                continue
            }
        }
    }
}

/// Call this when user leaves the feed view or app backgrounds.
func cancelPrefetching() {
    prefetchTask?.cancel()
}

private func isUnderMemoryPressure() -> Bool {
    // Rough heuristic: check available physical memory
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard kerr == KERN_SUCCESS else { return false }
    let usedMB = Double(info.resident_size) / 1_048_576
    return usedMB > 200  // Back off if app is using >200 MB
}
```

**Trigger in your feed view (e.g., `TodayView.swift`):**
```swift
.onAppear {
    viewModel.startPrefetching(viewModel.articles)
}
.onDisappear {
    viewModel.cancelPrefetching()
}
```

---

## Priority 5 — Progressive Content Rendering (Perceived load: 0.3s to first text)

**Problem:** SwiftUI waits for *all* ContentNodes to be ready before showing *any* content. Users see a blank screen during the entire 6 seconds.

**Solution:** Show a skeleton immediately, then reveal content progressively as it loads. Show the first batch of nodes (~10 paragraphs) as soon as they arrive, then append the rest.

**Update `ArticleReaderHostView.swift`:**
```swift
struct ArticleReaderHostView: View {
    let article: Article

    @State private var nodes: [ContentNode] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var extractionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isLoading && nodes.isEmpty {
                // Show skeleton immediately — user sees activity within 0.1s
                ArticleSkeletonView()
                    .transition(.opacity)
            }

            if !nodes.isEmpty {
                ArticleReaderView(nodes: nodes, isLoadingMore: isLoading)
                    .transition(.opacity)
            }

            if let error = loadError, nodes.isEmpty {
                ContentUnavailableView(
                    "Couldn't Load Article",
                    systemImage: "wifi.slash",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .animation(.easeInOut(duration: 0.25), value: nodes.isEmpty)
        .onAppear { startLoading() }
        .onDisappear { extractionTask?.cancel() }
    }

    private func startLoading() {
        extractionTask = Task {
            do {
                let result = try await ArticlePipelineService.shared.loadArticle(url: article.url)
                await MainActor.run {
                    withAnimation {
                        self.nodes = result
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.loadError = error
                    self.isLoading = false
                }
            }
        }
    }
}
```

**Add `ArticleSkeletonView.swift` in `Views/ArticleReader/`:**
```swift
import SwiftUI

struct ArticleSkeletonView: View {
    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title skeleton
            skeletonBar(width: 0.85, height: 28)
            skeletonBar(width: 0.6, height: 28)

            Spacer().frame(height: 4)

            // Byline skeleton
            skeletonBar(width: 0.4, height: 14)

            Divider().padding(.vertical, 8)

            // Paragraph skeletons
            ForEach(0..<4, id: \.self) { block in
                VStack(alignment: .leading, spacing: 8) {
                    skeletonBar(width: 1.0, height: 15)
                    skeletonBar(width: 1.0, height: 15)
                    skeletonBar(width: 0.7, height: 15)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .overlay(shimmerOverlay)
        .onAppear { startShimmer() }
    }

    @ViewBuilder
    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: geo.size.width * width, height: height)
        }
        .frame(height: height)
    }

    private var shimmerOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.35), location: 0.5),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 180)
        .offset(x: shimmerOffset)
        .clipped()
    }

    private func startShimmer() {
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            shimmerOffset = UIScreen.main.bounds.width + 180
        }
    }
}
```

**Update `ArticleReaderView.swift`** to use `LazyVStack` for efficient rendering of large articles:
```swift
struct ArticleReaderView: View {
    let nodes: [ContentNode]
    let isLoadingMore: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    contentView(for: node)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }

                if isLoadingMore {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading more…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func contentView(for node: ContentNode) -> some View {
        switch node.type {
        case .paragraph:
            ParagraphView(node: node)
        case .heading:
            HeadingView(node: node)
        case .blockquote:
            BlockquoteView(node: node)
        case .code:
            CodeBlockView(node: node)
        case .image:
            ArticleImageView(node: node)
                .padding(.horizontal, -20) // Full-bleed images
        case .table:
            TableView(node: node)
        case .list:
            ListItemsView(node: node)
        }
    }
}
```

---

## Priority 6 — Image Loading Optimization (Prevents layout blocking)

**Problem:** `ArticleImageView` may block the render pipeline if images are loaded synchronously or block the main thread.

**Solution:** Ensure all images are loaded asynchronously with placeholders, and that off-screen images use `.background` task priority.

**Update `ArticleImageView.swift`:**
```swift
struct ArticleImageView: View {
    let node: ContentNode

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if failed {
                Color(.systemGray6)
                    .frame(height: 200)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Color(.systemGray6)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .redacted(reason: .placeholder)
            }
        }
        .onAppear {
            guard image == nil && !isLoading, let url = node.imageURL else { return }
            loadImage(from: url)
        }
    }

    private func loadImage(from url: URL) {
        isLoading = true

        // Check URLCache first (free, no extra code needed)
        // URLSession will hit the cache automatically

        Task(priority: .medium) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let uiImage = UIImage(data: data)
                await MainActor.run {
                    withAnimation { self.image = uiImage }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.failed = true
                    self.isLoading = false
                }
            }
        }
    }
}
```

---

## Priority 7 — ContentNode Parsing Optimization (Saves ~400–600ms)

**Problem:** The current HTML→ContentNode parsing in `ContentNormalizerService.swift` may use a DOM-based parser (like `SwiftSoup`), which loads the entire HTML tree into memory before walking it.

**Solution:** Evaluate whether the parser can be replaced or supplemented with a SAX-based streaming approach using `XMLParser`, which is ~4x faster for large HTML documents.

**Consult and potentially refactor `ContentNormalizerService.swift`:**

If the current code uses SwiftSoup like this:
```swift
// Current (likely DOM-based — slow for large HTML):
let doc = try SwiftSoup.parse(html)
let paragraphs = try doc.select("p")
```

Consider replacing with streaming XMLParser for the initial extraction pass:
```swift
// Faster streaming approach:
class StreamingHTMLParser: NSObject, XMLParserDelegate {
    private(set) var nodes: [ContentNode] = []
    private var currentText = ""
    private var elementStack: [String] = []

    func parse(_ html: String) -> [ContentNode] {
        // Wrap in minimal XHTML envelope for XMLParser compatibility
        let wrapped = "<?xml version='1.0'?><body>\(html)</body>"
        guard let data = wrapped.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return nodes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName.lowercased())
        if ["p", "h1", "h2", "h3", "blockquote", "pre", "code"].contains(elementName.lowercased()) {
            currentText = ""
        }
        if elementName.lowercased() == "img", let src = attributes["src"],
           let url = URL(string: src) {
            flushText()
            nodes.append(ContentNode(type: .image, imageURL: url, altText: attributes["alt"]))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        defer { elementStack.removeLast() }
        let tag = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch tag {
        case "p":           nodes.append(ContentNode(type: .paragraph, text: text))
        case "h1":          nodes.append(ContentNode(type: .heading, level: 1, text: text))
        case "h2":          nodes.append(ContentNode(type: .heading, level: 2, text: text))
        case "h3":          nodes.append(ContentNode(type: .heading, level: 3, text: text))
        case "blockquote":  nodes.append(ContentNode(type: .blockquote, text: text))
        case "pre", "code": nodes.append(ContentNode(type: .code, text: text))
        default: break
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            if !currentText.isEmpty { currentText += " " }
            currentText += trimmed
        }
    }

    private func flushText() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            nodes.append(ContentNode(type: .paragraph, text: text))
            currentText = ""
        }
    }
}
```

> **Note to Claude:** Before implementing this, read the current `ContentNormalizerService.swift` to understand the exact ContentNode type structure and avoid breaking changes. Adapt the parser to use the existing `ContentNode` enum/struct exactly as defined.

---

## Priority 8 — Memory Pressure Safety

**Problem:** If too many articles are pre-cached and the device is under memory pressure, iOS may terminate the app.

**Solution:** Respond to `UIApplication.didReceiveMemoryWarningNotification` by clearing the in-memory NSCache and pausing background prefetch.

**Add to `ArticleCacheService.swift` (or `AppState.swift`):**
```swift
// In init():
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.memCache.removeAllObjects()
    // NSCache also auto-evicts — this is a safety flush
}
```

---

## Expected Performance After All Optimizations

| Scenario | Before | After |
|---|---|---|
| First open (cold cache) | ~6.0s | ~2.0–2.5s |
| First open (WKWebView warmed) | ~4.5s | ~1.5–2.0s |
| Repeat open (memory cache) | ~6.0s | ~0.05s |
| Repeat open (disk cache) | ~6.0s | ~0.2s |
| Pre-fetched article | ~6.0s | ~0.05s |
| Perceived time to first text | ~6.0s | ~0.3s (skeleton) |

---

## Implementation Order & Notes

1. **Start with Priority 1 (WKWebView Pool)** — this is the single biggest win and is self-contained
2. **Add Priority 2 (parallel fetch)** — tiny change in `ArticlePipelineService`, huge payoff
3. **Add Priority 3 (cache)** — transforms repeat opens to instant
4. **Add Priority 5 (skeleton + progressive render)** — dramatically improves perceived performance
5. **Add Priority 4 (prefetch)** — polish; makes the first open instant for most users
6. **Priorities 6–8** — polish and stability

> Before making any changes, always `Read` the current implementation of each file to understand the existing code structure. Do not break existing error handling, cancellation patterns, or the `ContentNode` model. Make incremental changes and test each one.

---

## Related Files to Read Before Implementing

- `ReadabilityExtractionService.swift` — understand current WKWebView usage and JS evaluation pattern
- `ContentFetcherService.swift` — understand how HTML is currently fetched
- `ArticlePipelineService.swift` — understand pipeline orchestration and error handling
- `ContentNormalizerService.swift` — understand ContentNode construction before touching parser
- `ContentNode.swift` — understand the exact ContentNode model (crucial for cache serialization)
- `ArticleCacheService.swift` + `ArticleCacheStore.swift` — understand existing cache before replacing
- `ArticleReaderHostView.swift` — understand current loading state management
- `AppState.swift` — find the right place to call `WebViewPool.shared.warmUp()`
