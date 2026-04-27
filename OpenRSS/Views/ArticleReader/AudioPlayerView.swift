//
//  AudioPlayerView.swift
//  OpenRSS
//
//  Inline audio player shown below the hero image when an article has an
//  audio enclosure (e.g. podcast episodes, audio articles).
//
//  Layout:
//    [play/pause icon]  [slider ─────●───────────]
//                       [0:45             12:30  ]
//
//  Uses AVFoundation for playback. Configures the .playback audio session
//  so audio continues if the ringer switch is muted.
//

import SwiftUI
import AVFoundation

// MARK: - AudioPlayerModel

@Observable
final class AudioPlayerModel {

    // MARK: - Playback State

    private(set) var isPlaying  = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    // MARK: - API

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        let p    = AVPlayer(playerItem: item)
        self.player = p

        // Watch item status so we can read a valid duration.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            let d = item.duration
            guard d.isValid, !d.isIndefinite else { return }
            DispatchQueue.main.async { self?.duration = d.seconds }
        }

        // Update current-time at 0.5 s intervals.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self, t.isValid, !t.isIndefinite else { return }
            self.currentTime = t.seconds
        }

        // Reset to the beginning when playback reaches the end.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying   = false
            self?.currentTime = 0
            self?.player?.seek(to: .zero)
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Route audio through the speaker even when the ringer is silent.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
    }

    /// Seek to an absolute position in seconds. Safe to call mid-drag.
    func seek(to seconds: Double) {
        currentTime = seconds
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver  { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation?.invalidate()
        player            = nil
        timeObserver      = nil
        endObserver       = nil
        statusObservation = nil
        isPlaying         = false
    }

    deinit { stop() }
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {

    let audioURL: URL

    @State private var model       = AudioPlayerModel()
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        HStack(spacing: 14) {

            // Play / Pause button
            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            // Scrubber + time labels
            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : model.currentTime },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(model.duration, 1)
                ) { editing in
                    isScrubbing = editing
                    if !editing {
                        model.seek(to: scrubValue)
                    }
                }
                .tint(Design.Colors.primary)

                HStack {
                    Text(formatTime(isScrubbing ? scrubValue : model.currentTime))
                    Spacer()
                    Text(formatTime(model.duration))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear    { model.load(url: audioURL) }
        .onDisappear { model.stop() }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
