//
//  VideoEmbedView.swift
//  OpenRSS
//
//  Renders a tappable video thumbnail for ContentNode.videoEmbed.
//  Tapping opens the video URL in SFSafariViewController.
//

import SwiftUI

struct VideoEmbedView: View {

    let url: URL
    let thumbnailURL: URL?

    @State private var showSafari = false

    var body: some View {
        Button { showSafari = true } label: {
            ZStack {
                thumbnailBackground
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                playButton
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 4)
        .sheet(isPresented: $showSafari) {
            SafariView(url: url).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var thumbnailBackground: some View {
        if let thumbnailURL {
            CachedImageView(
                url: thumbnailURL,
                pointSize: CGSize(width: 400, height: 225),
                contentMode: .fill
            ) {
                videoPlaceholder
            }
        } else {
            videoPlaceholder
        }
    }

    private var videoPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.85))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var playButton: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
                .frame(width: 60, height: 60)
            Image(systemName: "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .offset(x: 2)
        }
    }
}
