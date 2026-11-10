import AVFoundation
import SwiftUI

/// Full-screen playback for a video card, with play/pause, a scrubbable timeline, and pinch
/// and double-tap zoom like photos.
///
/// Swiping the video left, right, or up decides like on the card; swiping down just closes.
/// While zoomed, one finger pans instead. Pressing and holding plays at 2x until the finger
/// lifts; VoiceOver gets an action for it instead.
struct VideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    /// Overlay text for each direction.
    var label: (SwipeDirection) -> String = { _ in "" }
    /// Called once a decision swipe has flown the video off. The caller closes the preview.
    var onDecide: (SwipeDirection) -> Void = { _ in }

    @State private var playback = VideoPlayback()
    @State private var showsControls = true
    @State private var swipe = PreviewDrag()
    @State private var zoom = ZoomTransform()
    /// The screen the video is fitted into.
    @State private var size = CGSize.zero
    @State private var posterSize = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.opacity(swipe.backdropOpacity).ignoresSafeArea()
            // Gestures cover the whole screen; only the video itself moves.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .overlay { video }
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                // The controls sit above, unzoomed, so their buttons and the timeline's own
                // drag keep working.
                .zoomable($zoom, content: videoSize, container: size, swipe: swipe, onSwipe: finish, onHold: hold) {
                    withAnimation(DS.Motion.calm) { showsControls.toggle() }
                }
                .accessibilityActions {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { decide(direction) }
                    }
                    if playback.isReady {
                        // No holding under VoiceOver: 2x stays on until turned off, pausing, or scrubbing.
                        if playback.isBoosted {
                            Button("Play at normal speed") { setBoost(false, restoring: false) }
                        } else {
                            Button("Play at 2x speed") { setBoost(true) }
                        }
                    }
                }
        }
        .overlay(alignment: .top) {
            if playback.isBoosted {
                Chip(text: "2x", systemImage: "forward.fill", style: .frosted)
                    // Below the top bar, which may or may not be showing.
                    .padding(.top, 76)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                    .accessibilityLabel("Playing at 2x speed")
                    .accessibilityIdentifier("video.speedPill")
            }
        }
        .overlay(alignment: .top) {
            if showsControls {
                topBar
                    .opacity(swipe.chromeOpacity)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showsControls {
                controls
                    .opacity(swipe.chromeOpacity)
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .task { await playback.load(item) }
        .onDisappear { playback.stop() }
    }

    private var video: some View {
        ZStack {
            if !playback.isReady {
                ItemImage(item.image, contentMode: .fit) { posterSize = $0 }
                    .overlay { ProgressView().tint(.white) }
            }
            PlayerLayerView(player: playback.player)
                .opacity(playback.isReady ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(width: videoSize.width, height: videoSize.height)
        .scaleEffect(zoom.scale)
        .offset(zoom.offset)
        .overlay { SwipeOverlay(offset: swipe.decideOffset, label: label) }
        .scaleEffect(swipe.contentScale)
        .rotationEffect(.degrees(swipe.rotation))
        .offset(swipe.offset)
    }

    /// The video fitted to the screen, from the poster until the clip's own size is known.
    private var videoSize: CGSize {
        let natural = playback.videoSize == .zero ? posterSize : playback.videoSize
        guard natural.width > 0, natural.height > 0 else { return size }
        return AVMakeRect(aspectRatio: natural, insideRect: CGRect(origin: .zero, size: size)).size
    }

    private func hold(_ isDown: Bool) {
        guard playback.isReady || !isDown else { return }
        setBoost(isDown)
    }

    private func setBoost(_ on: Bool, restoring: Bool = true) {
        withAnimation(DS.Motion.calm) {
            if on {
                guard !playback.isBoosted else { return }
                playback.beginBoost()
                Haptics.advance()
            } else {
                playback.endBoost(restoring: restoring)
            }
        }
    }

    private func finish(_ outcome: PreviewDrag.Outcome) {
        switch outcome {
        case .dismiss: dismiss()
        case .decide(let direction): decide(direction)
        }
    }

    private func decide(_ direction: SwipeDirection) {
        swipe.flyOut(direction) { onDecide(direction) }
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
    /// Playing at `boostRate` for a press-and-hold (or VoiceOver's 2x action).
    private(set) var isBoosted = false
    /// The clip's display size, rotation applied. Zero until loaded.
    private(set) var videoSize = CGSize.zero

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var wasPlayingBeforeScrub = false
    @ObservationIgnored private var wasPlayingBeforeBoost = false
    @ObservationIgnored private var isScrubbing = false
    /// Seeks chase the finger: while one is in flight, only the latest target is kept.
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeek: TimeInterval?

    /// The video track's size as shown, after rotation. Read off the main actor, where the tracks stay.
    private nonisolated static func uprightSize(of asset: AVAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let geometry = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rotated = geometry.0.applying(geometry.1)
        return CGSize(width: abs(rotated.width), height: abs(rotated.height))
    }

    func load(_ item: LibraryItem) async {
        duration = item.duration ?? 0
        guard let playerItem = await VideoSource.playerItem(for: item), !Task.isCancelled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.replaceCurrentItem(with: playerItem)
        if let loaded = try? await playerItem.asset.load(.duration), loaded.isNumeric, loaded.seconds > 0 {
            duration = loaded.seconds
        }
        if let size = await Self.uprightSize(of: playerItem.asset) {
            videoSize = size
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
        // `play()` starts at the default rate, so a boost survives a play from paused.
        player.defaultRate = isBoosted ? Self.boostRate : 1
        player.play()
        isPlaying = true
    }

    /// Pausing also drops any boost: the next play is at normal speed.
    func pause() {
        player.pause()
        isPlaying = false
        if isBoosted {
            isBoosted = false
            player.defaultRate = 1
        }
    }

    static let boostRate: Float = 2

    /// Plays at 2x, starting playback if it was paused. `endBoost` puts it back.
    func beginBoost() {
        guard !isBoosted else { return }
        wasPlayingBeforeBoost = isPlaying
        isBoosted = true
        play()
        player.rate = Self.boostRate
    }

    /// Back to normal speed. With `restoring`, a clip that was paused before the boost pauses
    /// again; without, it keeps playing at 1x.
    func endBoost(restoring: Bool = true) {
        guard isBoosted else { return }
        isBoosted = false
        player.defaultRate = 1
        if restoring, !wasPlayingBeforeBoost {
            pause()
        } else if isPlaying {
            player.rate = 1
        }
    }

    func beginScrubbing() {
        endBoost()
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
        endBoost()
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
                self.isBoosted = false
                self.player.defaultRate = 1
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
        // `layerClass` guarantees the layer's type, so this cast can't fail.
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#if DEBUG
#Preview {
    VideoPreviewView(item: PreviewSamples.video)
}
#endif
