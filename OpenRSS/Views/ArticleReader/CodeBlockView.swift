//
//  CodeBlockView.swift
//  OpenRSS
//
//  Phase 5 — renders a codeBlock ContentNode in a monospaced, scrollable block.
//

import SwiftUI

struct CodeBlockView: View {

    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(14)
                .fixedSize(horizontal: true, vertical: false)
        }
        .background(
            Color(.secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
