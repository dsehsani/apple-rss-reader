//
//  SyncFailedBanner.swift
//  Payam
//
//  Inline banner shown at the top of the river list when the last refresh
//  couldn't reach `/v1/river`. Pull-to-refresh is the retry action; the
//  banner clears automatically on the next successful sync (handled by
//  `RiverViewModel.syncFailed`).
//

import SwiftUI

struct SyncFailedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            Text("Couldn't reach server — pull to try again")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing.cardPadding)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .stroke(Design.Colors.subtleBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    SyncFailedBanner()
        .padding()
}
