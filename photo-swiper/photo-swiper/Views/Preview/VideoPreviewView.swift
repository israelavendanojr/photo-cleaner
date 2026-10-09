import AVFoundation
import SwiftUI

/// Full-screen playback for a video card, with play/pause and a scrubbable timeline.
///
/// Only for watching: decisions still happen on the card once this closes, except from the
/// pending pile, which passes `onKeep` to offer taking the video back out.
struct VideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    /// Shows a "Keep instead" button under the controls that calls this and closes.
    var onKeep: (() -> Void)?

    @State private var playback = VideoPlayback()
    @State private var showsControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !playback.isReady {
                ItemImage(item.image)
                    .ignoresSafeArea()
                    .overlay { ProgressView().tint(.white) }
            }
            PlayerLayerView(player: playback.player)
                .ignoresSafeArea()
                .opacity(playback.isReady ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DS.Motion.calm) { showsControls.toggle() }
                }
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            if showsControls { topBar.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if showsControls { controls.transition(.opacity) }
        }
        .environment(\.colorScheme, .dark)
        .task { await playback.load(item) }
        .onDisappear { playback.stop() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Close")
            Spacer(minLength: DS.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.size(item.bytes))
                    .font(.footnote.weight(.semibold))
                Text(Format.day(item.date))
                    .font(.footnote)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.s)
        .padding(.bottom, DS.Spacing.xl)
        .background {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: DS.Spacing.s) {
            Timeline(playback: playback)
            HStack {
                Text(Format.duration(playback.currentTime))
                Spacer()
                Button(action: playback.togglePlay) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!playback.isReady)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Spacer()
                Text("-" + Format.duration(max(playback.duration - playback.currentTime, 0)))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            if let onKeep {
                KeepInsteadButton(onKeep: onKeep)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

/// A thin track with a draggable thumb. Dragging pauses playback and seeks frame-accurately;
/// letting go resumes if it was playing.
private struct Timeline: View {
    let playback: VideoPlayback
    @State private var isDragging = false

    private var fraction: Double {
        playback.duration > 0 ? min(max(playback.currentTime / playback.duration, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let track: CGFloat = isDragging ? 6 : 4
            let thumb: CGFloat = isDragging ? 20 : 14
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                    .frame(height: track)
                Capsule().fill(.white)
                    .frame(width: width * fraction, height: track)
                Circle().fill(.white)
                    .frame(width: thumb, height: thumb)
                    .offset(x: width * fraction - thumb / 2)
                    .shadow(color: .black.opacity(0.3), radius: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            withAnimation(DS.Motion.calm) { isDragging = true }
                            playback.beginScrubbing()
                        }
                        playback.scrub(to: value.location.x / max(width, 1))
                    }
                    .onEnded { _ in
                        withAnimation(DS.Motion.calm) { isDragging = false }
                        playback.endScrubbing()
                    }
            )
        }
        .frame(height: 32)
        .disabled(!playback.isReady)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(Format.duration(playback.currentTime)) of \(Format.duration(playback.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.skip(by: 5)
            case .decrement: playback.skip(by: -5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("videoScrubber")
    }
}

// MARK: - Playback state

/// Owns the player and mirrors its clock for the UI.
@Observable
@MainActor
final class VideoPlayback {
    let player = AVPlayer()
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isReady = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var wasPlayingBeforeScrub = false
    @ObservationIgnored private var isScrubbing = false
    /// Seeks chase the finger: while one is in flight, only the latest target is kept.
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeek: TimeInterval?

    func load(_ item: LibraryItem) async {
        duration = item.duration ?? 0
        guard let playerItem = await VideoSource.playerItem(for: item), !Task.isCancelled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.replaceCurrentItem(with: playerItem)
        if let loaded = try? await playerItem.asset.load(.duration), loaded.isNumeric, loaded.seconds > 0 {
            duration = loaded.seconds
        }
        observe(playerItem)
        isReady = true
        play()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        if duration > 0, currentTime >= duration - 0.05 {
            // At the end: start over.
            currentTime = 0
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func beginScrubbing() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        pause()
    }

    /// `fraction` of the way through, clamped to 0...1.
    func scrub(to fraction: Double) {
        seek(to: min(max(fraction, 0), 1) * duration)
    }

    func endScrubbing() {
        isScrubbing = false
        if wasPlayingBeforeScrub { play() }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: min(max(currentTime + seconds, 0), duration))
    }

    func stop() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Internals

    private func seek(to seconds: TimeInterval) {
        currentTime = seconds
        guard !isSeeking else {
            pendingSeek = seconds
            return
        }
        isSeeking = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                if let next = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(to: next)
                }
            }
        }
    }

    private func observe(_ playerItem: AVPlayerItem) {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, !self.isSeeking else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }
}

/// An `AVPlayerLayer` with no system controls, so the preview's own controls are the only ones.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#Preview {
    VideoPreviewView(item: PreviewSamples.video)
}
