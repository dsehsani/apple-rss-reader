# OPML Import & Export — Implementation Guide

**Project:** OpenRSS (AppleRSS)  
**Target:** iOS 17+, SwiftUI, SwiftData  
**Scope:** Add OPML 2.0 import and export support so users can move their feed subscriptions to/from other RSS readers.

---

## Overview

OPML (Outline Processor Markup Language) is the standard interchange format for RSS feed lists. This feature has two halves:

- **Export:** Serialize `FolderModel` + `FeedModel` objects from SwiftData into a valid OPML 2.0 XML file and present a share sheet.
- **Import:** Parse an OPML file the user picks, create `FolderModel` and `FeedModel` objects via `SwiftDataService`, and skip duplicates.

Neither half has any dependency on onboarding or any other unfinished feature.

---

## File Structure to Create

```
OpenRSS/Services/
  OPMLService.swift          ← All import + export logic

OpenRSS/Views/Settings/
  SettingsView.swift         ← Modify existing file: add import/export buttons
```

That's it — two touch points.

---

## Part 1: OPMLService.swift

Create this file at `OpenRSS/Services/OPMLService.swift`.

### Responsibilities

- `export(folders:unfiledFeeds:) -> URL` — builds OPML XML, writes to a temp file, returns its URL for the share sheet.
- `importFromURL(_ url: URL, into service: SwiftDataService) async throws` — parses OPML, creates folders and feeds.

### Full Implementation

```swift
//
//  OPMLService.swift
//  OpenRSS
//
//  OPML 2.0 import and export for feed subscriptions.
//

import Foundation
import SwiftData

// MARK: - Errors

enum OPMLError: LocalizedError {
    case unreadableFile
    case malformedXML
    case noFeedsFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:  return "The selected file could not be read."
        case .malformedXML:    return "The file is not valid OPML."
        case .noFeedsFound:    return "No feeds were found in this OPML file."
        }
    }
}

// MARK: - OPMLService

final class OPMLService: NSObject {

    static let shared = OPMLService()
    private override init() {}

    // MARK: - Export

    /// Builds an OPML 2.0 file from the user's current folders and feeds.
    /// Unfiled feeds go into a synthetic "Unfiled" group in the output.
    /// Returns a URL to a temp file suitable for passing to a share sheet.
    func export(folders: [FolderModel], unfiledFeeds: [FeedModel]) throws -> URL {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>OpenRSS Subscriptions</title>
            <dateCreated>\(rfc822Date(Date()))</dateCreated>
          </head>
          <body>\n
        """

        // Folders with their feeds
        for folder in folders.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let feeds = folder.feeds.sorted(by: { $0.title < $1.title })
            guard !feeds.isEmpty else { continue }

            xml += "    <outline text=\"\(escaped(folder.name))\" title=\"\(escaped(folder.name))\">\n"
            for feed in feeds {
                xml += feedOutline(feed, indent: "      ")
            }
            xml += "    </outline>\n"
        }

        // Unfiled feeds (no parent folder)
        if !unfiledFeeds.isEmpty {
            xml += "    <outline text=\"Unfiled\" title=\"Unfiled\">\n"
            for feed in unfiledFeeds.sorted(by: { $0.title < $1.title }) {
                xml += feedOutline(feed, indent: "      ")
            }
            xml += "    </outline>\n"
        }

        xml += "  </body>\n</opml>"

        // Write to a temp file
        let fileName = "openrss-subscriptions-\(isoDateStamp(Date())).opml"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try xml.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    // MARK: - Import

    /// Parses an OPML file and creates folders + feeds via SwiftDataService.
    /// Skips feeds whose feedURL already exists. Must be called on MainActor
    /// because SwiftDataService mutation methods are @MainActor.
    @MainActor
    func importFromURL(_ url: URL, into service: SwiftDataService) async throws -> OPMLImportResult {
        // Resolve security-scoped resource if coming from Files app
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw OPMLError.unreadableFile }

        let parser = OPMLParser(data: data)
        guard let parsed = parser.parse() else { throw OPMLError.malformedXML }
        guard !parsed.isEmpty else { throw OPMLError.noFeedsFound }

        // Build a set of existing feed URLs to skip duplicates
        let existingURLs = Set(service.sources.map { $0.feedURL.lowercased() })

        var imported = 0
        var skipped  = 0

        for group in parsed {
            // Create folder if it has a real name (skip "Unfiled" synthetic group)
            var folderID: UUID? = nil
            if let groupName = group.name, !groupName.isEmpty, groupName.lowercased() != "unfiled" {
                // Reuse existing folder with same name, or create new
                if let existing = service.categories.first(where: { $0.name == groupName }) {
                    folderID = existing.id
                } else {
                    try await service.addFolder(name: groupName, iconName: "folder.fill", colorHex: "007AFF")
                    folderID = service.categories.last?.id
                }
            }

            for feed in group.feeds {
                let normalizedURL = feed.feedURL.lowercased()
                guard !existingURLs.contains(normalizedURL) else {
                    skipped += 1
                    continue
                }
                try await service.addFeed(
                    feedURL: feed.feedURL,
                    title: feed.title ?? feed.feedURL,
                    websiteURL: feed.htmlURL ?? "",
                    folderID: folderID
                )
                imported += 1
            }
        }

        return OPMLImportResult(imported: imported, skipped: skipped)
    }

    // MARK: - Private Helpers

    private func feedOutline(_ feed: FeedModel, indent: String) -> String {
        var line = "\(indent)<outline"
        line += " type=\"rss\""
        line += " text=\"\(escaped(feed.title))\""
        line += " title=\"\(escaped(feed.title))\""
        line += " xmlUrl=\"\(escaped(feed.feedURL))\""
        if !feed.websiteURL.isEmpty {
            line += " htmlUrl=\"\(escaped(feed.websiteURL))\""
        }
        line += "/>\n"
        return line
    }

    private func escaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
    }

    private func rfc822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }

    private func isoDateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Result Type

struct OPMLImportResult {
    let imported: Int
    let skipped: Int

    var summary: String {
        if skipped == 0 {
            return "Imported \(imported) feed\(imported == 1 ? "" : "s")."
        } else {
            return "Imported \(imported) feed\(imported == 1 ? "" : "s"), skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")."
        }
    }
}

// MARK: - OPMLParser (SAX-based)

/// Parses OPML XML into a flat list of feed groups using XMLParser.
private final class OPMLParser: NSObject, XMLParserDelegate {

    struct FeedEntry {
        let title: String?
        let feedURL: String
        let htmlURL: String?
    }

    struct FeedGroup {
        let name: String?
        var feeds: [FeedEntry]
    }

    private let data: Data
    private var groups: [FeedGroup] = []
    private var currentGroup: FeedGroup? = nil
    private var parseError = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [FeedGroup]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        let success = parser.parse()
        guard success, !parseError else { return nil }
        // Flush the last open group
        if let g = currentGroup { groups.append(g) }
        return groups
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let xmlURL = attributes["xmlUrl"] ?? attributes["xmlurl"] ?? attributes["XMLURL"] ?? ""
        let htmlURL = attributes["htmlUrl"] ?? attributes["htmlurl"] ?? attributes["HTMLURL"]
        let text = attributes["text"] ?? attributes["title"] ?? ""

        if xmlURL.isEmpty {
            // This is a folder/group outline — flush previous group and start new
            if let g = currentGroup { groups.append(g) }
            currentGroup = FeedGroup(name: text.isEmpty ? nil : text, feeds: [])
        } else {
            // This is a feed outline
            let entry = FeedEntry(
                title: text.isEmpty ? nil : text,
                feedURL: xmlURL,
                htmlURL: htmlURL
            )
            if currentGroup != nil {
                currentGroup!.feeds.append(entry)
            } else {
                // Feed at root level with no parent group — treat as unfiled
                if groups.last?.name == nil {
                    groups[groups.count - 1].feeds.append(entry)
                } else {
                    groups.append(FeedGroup(name: nil, feeds: [entry]))
                }
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = true
    }
}
```

---

## Part 2: Modify SettingsView.swift

### What to Add

Inside `SettingsView`, there is already a `dataSection` computed property. Add the OPML import/export UI there.

### New State Properties

Add these to the top of `SettingsView` alongside the existing `@State` properties:

```swift
// OPML
@State private var isExporting = false
@State private var isImporting = false
@State private var exportFileURL: URL? = nil
@State private var opmlAlert: OPMLAlertItem? = nil

// Environment access to SwiftDataService
@Environment(SwiftDataService.self) private var dataService
```

### Alert Helper Type

Add this outside the `SettingsView` struct (or as a nested type inside it):

```swift
struct OPMLAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
```

### Updated `dataSection`

Replace the existing `dataSection` body with:

```swift
var dataSection: some View {
    settingsSection(title: "Data", icon: "externaldrive") {
        // --- existing rows (keep whatever was there) ---

        // OPML Export
        settingsButton(
            title: "Export Subscriptions",
            subtitle: "Save feeds as OPML file",
            color: .blue
        ) {
            exportOPML()
        }

        // OPML Import
        settingsButton(
            title: "Import Subscriptions",
            subtitle: "Add feeds from OPML file",
            color: .green
        ) {
            isImporting = true
        }
    }
    // Share sheet for export
    .sheet(isPresented: $isExporting) {
        if let url = exportFileURL {
            ShareSheet(activityItems: [url])
        }
    }
    // File picker for import
    .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.xml, .data],  // .opml not a standard UTType; .xml covers it
        allowsMultipleSelection: false
    ) { result in
        handleImportResult(result)
    }
    // Result/error alert
    .alert(item: $opmlAlert) { alert in
        Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            dismissButton: .default(Text("OK"))
        )
    }
}
```

### Helper Methods

Add these methods inside `SettingsView`:

```swift
// MARK: - OPML Export

private func exportOPML() {
    // Gather unfiled feeds (feeds with no folder)
    let allFeeds = dataService.sources
    let filedIDs = Set(
        dataService.categories.flatMap { cat in
            dataService.sources
                .filter { $0.categoryID == cat.id }
                .map { $0.id }
        }
    )

    // Pull the raw FolderModels and FeedModels from SwiftDataService
    // We need FolderModel/FeedModel directly since OPMLService reads them
    let folders: [FolderModel] = dataService.categories.compactMap { cat in
        dataService.folderModel(for: cat.id)
    }

    let unfiledFeeds: [FeedModel] = allFeeds
        .filter { $0.categoryID == SwiftDataService.unfiledFolderID }
        .compactMap { source in
            // Match back to FeedModel by ID
            folders.flatMap { $0.feeds }.first(where: { $0.id == source.id })
            // For unfiled, query directly — see note below
        }

    // NOTE: SwiftDataService does not currently expose a direct
    // `feedModel(for:)` method for unfiled feeds. The cleanest approach
    // is to add a helper, OR pass `folders` + an unfiled feeds array
    // by querying ModelContext directly. See "SwiftDataService Extension"
    // section below for the recommended addition.

    do {
        let url = try OPMLService.shared.export(folders: folders, unfiledFeeds: [])
        exportFileURL = url
        isExporting = true
    } catch {
        opmlAlert = OPMLAlertItem(
            title: "Export Failed",
            message: error.localizedDescription
        )
    }
}

// MARK: - OPML Import

private func handleImportResult(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
        opmlAlert = OPMLAlertItem(title: "Import Failed", message: error.localizedDescription)

    case .success(let urls):
        guard let url = urls.first else { return }
        Task { @MainActor in
            do {
                let importResult = try await OPMLService.shared.importFromURL(url, into: dataService)
                opmlAlert = OPMLAlertItem(title: "Import Complete", message: importResult.summary)
            } catch {
                opmlAlert = OPMLAlertItem(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
}
```

### ShareSheet Helper

Add this helper view to the Settings folder (or a Utilities file):

```swift
import UIKit
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

---

## Part 3: SwiftDataService Extension (Required)

`exportOPML()` in SettingsView needs access to the raw `FolderModel` and unfiled `FeedModel` objects. `folderModel(for:)` already exists on `SwiftDataService`, but there is no equivalent for unfiled feeds.

Add this method to `SwiftDataService`:

```swift
/// Returns the raw FeedModel for a given feed ID, regardless of folder.
@MainActor
func feedModel(for id: UUID) -> FeedModel? {
    guard let context = modelContext else { return nil }
    let descriptor = FetchDescriptor<FeedModel>(
        predicate: #Predicate { $0.id == id }
    )
    return try? context.fetch(descriptor).first
}

/// Returns all FeedModels that have no folder assigned.
@MainActor
func unfiledFeedModels() -> [FeedModel] {
    guard let context = modelContext else { return [] }
    let descriptor = FetchDescriptor<FeedModel>(
        predicate: #Predicate { $0.folder == nil }
    )
    return (try? context.fetch(descriptor)) ?? []
}
```

Then update `exportOPML()` in SettingsView to call `dataService.unfiledFeedModels()` instead of the placeholder.

---

## Part 4: Wire SwiftDataService into SettingsView

`SettingsView` currently does not receive `SwiftDataService` from the environment. Confirm it is injected at the call site.

In the parent view that presents `SettingsView` (likely inside `MainTabView` or the tab's destination), ensure:

```swift
SettingsView()
    .environment(SwiftDataService.shared)
```

If `SwiftDataService.shared` is already injected at the root (in `OpenRSSApp.body`), it propagates automatically and no change is needed.

---

## OPML Format Reference

The export produces this structure:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>OpenRSS Subscriptions</title>
    <dateCreated>Thu, 17 Apr 2026 10:00:00 +0000</dateCreated>
  </head>
  <body>
    <outline text="Tech News" title="Tech News">
      <outline type="rss" text="The Verge" title="The Verge"
               xmlUrl="https://www.theverge.com/rss/index.xml"
               htmlUrl="https://www.theverge.com"/>
    </outline>
    <outline text="Unfiled" title="Unfiled">
      <outline type="rss" text="Hacker News" title="Hacker News"
               xmlUrl="https://news.ycombinator.com/rss"
               htmlUrl="https://news.ycombinator.com"/>
    </outline>
  </body>
</opml>
```

The parser handles both grouped (folder > feed) and flat (root-level feed) layouts from third-party apps.

---

## Testing Checklist

- [ ] Export with folders containing feeds → valid OPML file produced
- [ ] Export with unfiled feeds → appear under `<outline text="Unfiled">`
- [ ] Export with empty feed list → empty body, no crash
- [ ] Import a well-formed OPML (e.g. exported from Reeder, NetNewsWire) → feeds + folders created
- [ ] Import with duplicate URLs → duplicates skipped, correct count reported in alert
- [ ] Import a flat OPML (no folder grouping) → feeds created as unfiled
- [ ] Import an invalid XML file → `OPMLError.malformedXML` alert shown
- [ ] Import a valid XML with no `xmlUrl` attributes → `OPMLError.noFeedsFound` alert shown
- [ ] Share sheet appears on export tap → file can be saved to Files, AirDropped, emailed
- [ ] File picker appears on import tap → `.opml` and `.xml` files selectable

---

## Notes for the Agent

- Do **not** use `XMLDocument` — it is macOS-only. The SAX-based `XMLParser` (Foundation) is the right tool for iOS.
- The `.fileImporter` modifier's `allowedContentTypes` uses `[.xml, .data]` because `.opml` is not a registered `UTType` on iOS. This is correct and intentional.
- `OPMLService` is a plain `final class` (not `@Observable`, not `@MainActor`) because it has no state — it's purely functional. Only the `importFromURL` method is `@MainActor` because it calls `SwiftDataService` mutating methods.
- `addFolder` and `addFeed` on `SwiftDataService` are both `@MainActor throws` — the `Task { @MainActor in }` block in `handleImportResult` ensures thread safety.
- The export helper `exportOPML()` calls `dataService.folderModel(for:)` which is already implemented on `SwiftDataService` — no new SwiftData queries needed for the folder side.
