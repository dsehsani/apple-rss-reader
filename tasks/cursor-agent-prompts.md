# Cursor Agent Prompts — Awaab-Dev Feature Integration

> **Branch context:** We are on `feat/heroes-and-async-crud`. Awaab's work lives on
> `awaab-dev`. For each agent below, your first move is to inspect the relevant file(s)
> on `awaab-dev` using `git show awaab-dev:<path>` so you can see what Awaab actually
> built before you touch anything on the current branch.
>
> **Do NOT port** anything related to Awaab's API / chatbot / summarisation feature.
> Only the four features listed below are in scope.

---

## Agent 1 — Paywall Detection
**Model: `claude-3.7-sonnet`**

```
You are working in an iOS SwiftUI RSS reader app called OpenRSS, on the branch
`feat/heroes-and-async-crud`.

### Background

The `Article` model (OpenRSS/Models/Article.swift) already has an `isPaywalled: Bool`
field. `ArticleCardView` (OpenRSS/Views/Components/ArticleCardView.swift) already
renders a "Subscription may be required" badge when `article.isPaywalled || source?.isPaywalled == true`.
`ArticleReaderView` (OpenRSS/Views/ArticleReader/ArticleReaderView.swift) already
shows a "Hitting a paywall? Sign in here" footnote.

The stub file `OpenRSS/Utilities/PaywallDetector.swift` currently contains nothing
but an empty enum:

    enum PaywallDetector {}

### Your job

1. Run: `git show awaab-dev:OpenRSS/Utilities/PaywallDetector.swift`
   Read Awaab's full implementation carefully.

2. Port his PaywallDetector logic into the current branch's
   `OpenRSS/Utilities/PaywallDetector.swift`. Preserve the existing file header
   comment (lines 1–7) and replace the empty `enum PaywallDetector {}` body with
   his implementation.

3. Find where in the pipeline `isPaywalled` should be set. The most likely
   integration points are:
   - `OpenRSS/Services/ArticlePipelineService.swift` — after content extraction
   - `OpenRSS/Services/ContentNormalizerService.swift` — after HTML parsing
   - `OpenRSS/Services/FeedIngestService.swift` — at ingest time
   
   Check `git show awaab-dev:<file>` for each of those files to see if Awaab wired
   detection there, then mirror that wiring on the current branch.

4. Do NOT touch anything related to an AI API, OpenAI, summarization endpoint, or
   chat feature — skip any such code you encounter in awaab-dev.

5. Build the app (Cmd+B) and confirm no compile errors before finishing.

### Success criteria
- `PaywallDetector.swift` is no longer an empty stub.
- The paywall badge in `ArticleCardView` lights up for articles/sources that trigger
  Awaab's detection heuristics.
- No new compile errors introduced.
```

---

## Agent 2 — Hero Image
**Model: `claude-3.5-sonnet`**

```
You are working in an iOS SwiftUI RSS reader app called OpenRSS, on the branch
`feat/heroes-and-async-crud`.

### Background

The current branch already has a full hero-image stack:
- `OpenRSS/Services/OGImageService.swift` — actor that fetches og:image from
  article pages, with UserDefaults caching and negative-cache TTL.
- `OpenRSS/Services/HeroPrefetcher.swift` — bounded, time-budgeted batch prefetch
  used by the river pipeline and background refresh tasks.
- `OpenRSS/Services/ThumbnailService.swift` — on-disk JPEG downsampling cache.
- `OpenRSS/Views/Components/CachedImageView.swift` — image component used by cards.
- `OpenRSS/Views/Components/ArticleCardView.swift` — displays hero at 180pt height
  with feed-URL → og:image fallback on failure.
- `OpenRSS/Views/ArticleReader/ArticleReaderView.swift` — displays hero at 220pt
  in the reader header zone.

### Your job

1. Run each of the following and read the output carefully:
   ```
   git show awaab-dev:OpenRSS/Services/OGImageService.swift
   git show awaab-dev:OpenRSS/Services/HeroPrefetcher.swift
   git show awaab-dev:OpenRSS/Services/ThumbnailService.swift
   git show awaab-dev:OpenRSS/Views/Components/CachedImageView.swift
   git show awaab-dev:OpenRSS/Views/Components/ArticleCardView.swift
   ```

2. Diff each file against the current branch version. Identify any improvements,
   bug fixes, or new behaviors Awaab added that are NOT in the current branch.

3. For each meaningful difference, apply it to the current branch file. Focus on:
   - Image resolution / sizing improvements
   - Cache invalidation or TTL changes
   - Layout or placeholder changes in ArticleCardView's heroImage subview
   - Any new fallback strategies

4. Do NOT port anything related to an AI API, OpenAI, summarization, or chat.

5. Build (Cmd+B) and confirm no compile errors.

### Success criteria
- All meaningful hero-image improvements from awaab-dev are reflected in the
  current branch without regressing the existing fallback logic.
- No new compile errors.
```

---

## Agent 3 — Audio Support
**Model: `claude-3.5-sonnet`**

```
You are working in an iOS SwiftUI RSS reader app called OpenRSS, on the branch
`feat/heroes-and-async-crud`.

### Background

Audio support is partially in place on the current branch:
- `OpenRSS/Views/ArticleReader/AudioPlayerView.swift` — AVFoundation-backed inline
  player (play/pause, scrubber, time labels). Already complete.
- `OpenRSS/Models/Article.swift` — has `audioURL: String?` field with backward-
  compatible custom decoder.
- `OpenRSS/Views/ArticleReader/ArticleReaderHostView.swift` — passes
  `article.audioURL.flatMap { URL(string: $0) }` into `ArticleReaderView`.
- `OpenRSS/Views/ArticleReader/ArticleReaderView.swift` — shows `AudioPlayerView`
  below the hero when `audioURL != nil`.

The possible gap is at the **RSS parsing layer**: `audioURL` on `Article` only
has value if the RSS parser extracts `<enclosure>` tags and maps them through.

### Your job

1. Read Awaab's versions of the following files:
   ```
   git show awaab-dev:OpenRSS/Services/RSSParserService.swift
   git show awaab-dev:OpenRSS/Models/RSSItem.swift
   git show awaab-dev:OpenRSS/Views/ArticleReader/AudioPlayerView.swift
   ```

2. In `OpenRSS/Models/RSSItem.swift`, check whether the current branch's `RSSItem`
   has an `audioURL` field. If Awaab added it, add it to the current branch too.

3. In `OpenRSS/Services/RSSParserService.swift`, check the RSS 2.0 and Atom mapping
   code. Confirm that `<enclosure url="..." type="audio/...">` tags are captured
   and stored in `RSSItem.audioURL`. If Awaab added that mapping and it's missing
   on the current branch, add it.

4. Check `OpenRSS/Services/ArticlePipelineService.swift` or `FeedIngestService.swift`
   to ensure `RSSItem.audioURL` flows through to `Article.audioURL`. Add the
   mapping if it's missing.

5. If Awaab made any improvements to `AudioPlayerView.swift` itself (UI tweaks,
   speed controls, chapter support, etc.), port those too.

6. Do NOT touch anything related to an AI API, OpenAI, summarization, or chat.

7. Build (Cmd+B) — no errors, no warnings from the audio path.

### Success criteria
- A podcast RSS feed item with an `<enclosure>` tag produces an `Article` whose
  `audioURL` is non-nil, causing `AudioPlayerView` to appear in the reader.
- No compile errors.
```

---

## Agent 4 — Video Detection
**Model: `claude-3.5-sonnet`**

```
You are working in an iOS SwiftUI RSS reader app called OpenRSS, on the branch
`feat/heroes-and-async-crud`.

### Background

YouTube video detection is fully implemented on the current branch:
- `OpenRSS/Services/YouTubeService.swift` — routes YouTube URLs into .video,
  .short, .playlist resources; provides thumbnail URLs and RSS-feed resolution.
- `OpenRSS/Services/YouTubeAtomParser.swift` — parses YouTube Atom feeds.
- `OpenRSS/Views/ArticleReader/ArticleReaderHostView.swift` — detects YouTube URLs
  in `runPipeline()` and switches to `.youtube(URL)` or `.playlist(URL)` load
  states, each with a full card UI.

What is NOT handled: **non-YouTube embedded video** (Vimeo, direct .mp4 links,
`<media:content>` enclosures in RSS feeds, etc.).

### Your job

1. Read Awaab's versions of the relevant files:
   ```
   git show awaab-dev:OpenRSS/Services/YouTubeService.swift
   git show awaab-dev:OpenRSS/Services/YouTubeAtomParser.swift
   git show awaab-dev:OpenRSS/Views/ArticleReader/ArticleReaderHostView.swift
   git show awaab-dev:OpenRSS/Models/ContentNode.swift
   git show awaab-dev:OpenRSS/Models/RSSItem.swift
   ```
   Also check if awaab-dev has any new file like `VideoDetector.swift`,
   `VideoPlayerView.swift`, or similar:
   ```
   git show awaab-dev:OpenRSS/Utilities/ 2>/dev/null || true
   git show awaab-dev:OpenRSS/Services/ 2>/dev/null | grep -i video || true
   ```

2. If Awaab added a `.video` case to `ContentNode`, add it to the current branch's
   `OpenRSS/Models/ContentNode.swift` and add a matching `case .video` handler in
   `ArticleReaderView.nodeView(for:)`.

3. If Awaab added non-YouTube video detection (Vimeo, direct video links,
   `<media:content>` parsing), port that logic. Keep the YouTube path intact —
   don't break the existing `.youtube` / `.playlist` load states.

4. If Awaab improved `YouTubeService.swift` or `YouTubeAtomParser.swift` (better
   thumbnail resolution, Shorts handling, channel-ID extraction), port those diffs.

5. Do NOT port anything related to an AI API, OpenAI, summarization endpoint,
   or chat feature.

6. Build (Cmd+B) — no errors.

### Success criteria
- YouTube video detection works as before (no regression).
- Any new video types Awaab added (Vimeo, direct MP4, media:content) are handled.
- No compile errors.
```
