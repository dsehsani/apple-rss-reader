//
//  VideoPlayerView.swift
//  OpenRSS
//
//  Inline video player shown below the hero image when an article has a
//  video enclosure (e.g. <media:content type="video/mp4">, <enclosure type="video/*">).
//
//  Mirrors AudioPlayerView — shown inside ArticleReaderView when the .loaded
//  path delivers an Article.videoURL that is not itself a standalone video URL
//  (those are handled by the .video LoadState in ArticleReaderHostView).
//

import SwiftUI
import AVKit

// MARK: - VideoPlayerView

struct VideoPlayerView: View {

    let videoURL: URL

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: videoURL)
                }
            }
            .onDisappear {
                player?.pause()
            }
    }
}
