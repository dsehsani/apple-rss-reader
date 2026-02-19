//
//  TableView.swift
//  OpenRSS
//
//  Phase 5 — renders a table ContentNode.
//  Horizontally scrollable so wide stat tables (NFL, NBA, etc.) don't get clipped.
//

import SwiftUI

struct TableView: View {

    let headers: [String]
    let rows: [[String]]

    // Compute a consistent column width based on the widest content in each column.
    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // Header row
                if !headers.isEmpty {
                    headerRow
                    Divider()
                }

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    dataRow(row, isEven: index.isMultiple(of: 2))
                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                Text(col < headers.count ? headers[col] : "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .lineLimit(2)
                    .frame(width: columnWidth(col), alignment: col == 0 ? .leading : .trailing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: - Data Row

    private func dataRow(_ row: [String], isEven: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                Text(col < row.count ? row[col] : "—")
                    .font(.caption)
                    .lineLimit(2)
                    .frame(width: columnWidth(col), alignment: col == 0 ? .leading : .trailing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .background(isEven ? Color.clear : Color(.systemFill).opacity(0.3))
    }

    // MARK: - Column Width

    /// First column (labels/names) gets more space; stat columns are narrower.
    private func columnWidth(_ col: Int) -> CGFloat {
        if columnCount <= 1 { return 200 }
        return col == 0 ? 140 : 72
    }
}
