//
//  ListItemsView.swift
//  OpenRSS
//
//  Phase 5 — renders a list ContentNode (ordered or unordered).
//

import SwiftUI

struct ListItemsView: View {

    let items: [String]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    // Bullet or number
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)

                    Text(item)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
