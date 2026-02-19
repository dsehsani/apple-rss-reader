//
//  BlockquoteView.swift
//  OpenRSS
//
//  Phase 5 — renders a blockquote ContentNode with a left-border accent.
//

import SwiftUI

struct BlockquoteView: View {

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: 3)

            Text(text)
                .font(.body)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            Color.accentColor.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
