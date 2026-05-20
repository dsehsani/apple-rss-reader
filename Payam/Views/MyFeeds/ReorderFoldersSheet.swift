//
//  ReorderFoldersSheet.swift
//  Payam
//
//  A modal sheet that lets the user drag folders into their preferred order.
//  The saved order is reflected immediately in the Today tab chips.
//
//  Adopted from Nathan's nathan-dev branch, adapted to Payam namespace.
//

import SwiftUI

struct ReorderFoldersSheet: View {

    // MARK: - Input

    /// Snapshot of folders in their current sort order.
    let folders: [Category]

    // MARK: - State

    /// Local mutable copy the user reorders before saving.
    @State private var ordered: [Category]

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Init

    init(folders: [Category]) {
        self.folders = folders
        _ordered = State(initialValue: folders)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { folder in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(folder.color.opacity(0.15))
                                    .frame(width: 36, height: 36)

                                Image(systemName: folder.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(folder.color)
                            }

                            Text(folder.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        ordered.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Drag folders to change their order. The Today tab chips will update to match.")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        .padding(.top, 4)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveOrder()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Save

    private func saveOrder() {
        SwiftDataService.shared.applyFolderOrder(ordered.map(\.id))
    }
}
