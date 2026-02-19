//
//  ParagraphView.swift
//  OpenRSS
//
//  Phase 5 — renders a paragraph ContentNode with tappable inline links.
//  Links embedded as "text (URL)" are extracted and displayed as underlined
//  tappable text via AttributedString.
//

import SwiftUI

struct ParagraphView: View {

    let text: String

    var body: some View {
        Text(attributedText)
            .font(.body)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                UIApplication.shared.open(url)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        // Detect " (https://...)" patterns and turn them into links
        var result = AttributedString(text)

        // Simple pass: find " (http" patterns
        let pattern = #" \((https?://[^\)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Build in reverse so ranges stay valid
        for match in matches.reversed() {
            let fullRange  = match.range          // " (URL)"
            let urlRange   = match.range(at: 1)   // "URL"

            guard let swiftFullRange = Range(fullRange, in: text),
                  let swiftURLRange  = Range(urlRange,  in: text),
                  let url = URL(string: String(text[swiftURLRange])),
                  let attrFullRange  = Range(swiftFullRange, in: result) else { continue }

            var linkAttr = AttributedString(" (link)")
            linkAttr.link = url
            linkAttr.foregroundColor = .accentColor
            linkAttr.underlineStyle = .single
            result.replaceSubrange(attrFullRange, with: linkAttr)
        }

        return result
    }
}
