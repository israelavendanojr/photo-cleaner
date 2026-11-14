import AVFoundation
import SwiftUI

/// Full-screen playback for a video, laid out after Photos' video editor: close and volume at the top,
/// the video in the middle, and at the bottom a play button beside the trim strip (`TrimStrip`).
///
/// The strip is the timeline. Moving either handle plays the selection on a loop and shows what the
/// trim would save, with Reset and Trim. Trim hands the selection to `onTrim`; nothing is exported until
/// the bin is confirmed. Leaving with the handles moved (close, a swipe down, a decision swipe) asks first:
/// save the trim, discard it, or keep editing. Without `onTrim`, or for a clip too short to trim, the
/// strip is a plain seek bar.
///
/// Pinch and double-tap zoom like photos. Swiping the video left, right, or up decides like on the card;
/// swiping down closes. While zoomed, one finger pans instead. Pressing and holding plays at 2x until the
/// finger lifts; VoiceOver gets an action for it instead.
struct VideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    /// Overlay text for each direction.
    var label: (SwipeDirection) -> String = { _ in "" }
    /// Called once a decision swipe has flown the video off. The caller closes the preview.
    var onDecide: (SwipeDirection) -> Void = { _ in }
    /// The trim waiting for this video, if any. The handles open where it left them.
    var savedTrim: PendingTrim?
    /// Called with the trim to save, or nil to keep the whole video (a saved trim dragged back to the ends).
    /// The caller closes the preview. Nil offers no trimming.
    var onTrim: ((PendingTrim?) -> Void)?

    @State private var playback = VideoPlayback()
    @State private var showsControls = true
    @State private var swipe = PreviewDrag()
    @State private var zoom = ZoomTransform()
    /// The screen the video is fitted into.
    @State private var size = CGSize.zero
    @State private var posterSize = CGSize.zero
    /// The handles, once the clip's length is known. Nil while loading, and when it can't be trimmed.
    @State private var draft: TrimDraft?
    /// A way out the user took with unsaved handles, held while the dialog asks about it.
    @State private var pendingExit: Exit?

    /// The ways out of the viewer that ask first when the handles have moved.
    private enum Exit: Equatable {
        case close
        case decide(SwipeDirection)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(swipe.backdropOpacity).ignoresSafeArea()
            // Gestures cover the whole screen; only the video itself moves.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .overlay { video }
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                // The controls sit above, unzoomed, so their buttons and the strip's own drags keep working.
                .zoomable($zoom, content: videoSize, container: size, swipe: swipe, onSwipe: finish, onHold: hold) {
                    withAnimation(DS.Motion.calm) { showsControls.toggle() }
                }
                .accessibilityActions {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { requestExit(.decide(direction)) }
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
        .confirmationDialog("Save this trim?", isPresented: isAskingToLeave, titleVisibility: .visible, presenting: pendingExit) { exit in
            Button("Save trim", action: saveTrim)
            Button("Discard", role: .destructive) { leave(exit) }
            Button("Keep editing", role: .cancel) {}
        } message: { _ in
            Text("You moved the trim handles. Nothing changes in your library until you clear the bin.")
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .task { await playback.load(item) }
        .onChange(of: playback.isReady) { setUpTrim() }
        .onChange(of: draft) { playback.setLoop(draft.flatMap { $0.isTrimmed ? $0.range : nil }) }
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
        case .dismiss: requestExit(.close)
        case .decide(let direction): requestExit(.decide(direction))
        }
    }

    // MARK: Leaving

    private var hasUnsavedTrim: Bool { draft?.hasUnsavedChanges ?? false }
    private var isTrimmed: Bool { draft?.isTrimmed ?? false }

    private var isAskingToLeave: Binding<Bool> {
        Binding(get: { pendingExit != nil }, set: { if !$0 { pendingExit = nil } })
    }

    /// Every way out comes through here. With the handles moved, the video settles back and the dialog asks.
    private func requestExit(_ exit: Exit) {
        guard hasUnsavedTrim else { return leave(exit) }
        swipe.cancel()
        pendingExit = exit
    }

    private func leave(_ exit: Exit) {
        pendingExit = nil
        switch exit {
        case .close: dismiss()
        case .decide(let direction): swipe.flyOut(direction) { onDecide(direction) }
        }
    }

    /// Hands the selection to the caller, which closes the viewer.
    private func saveTrim() {
        pendingExit = nil
        guard let draft, draft.hasUnsavedChanges else { return }
        onTrim?(draft.result)
    }

    /// Handles once the clip's length is known, where a saved trim left them. None without `onTrim` or
    /// for a clip too short to trim.
    private func setUpTrim() {
        guard onTrim != nil, draft == nil, playback.isReady, TrimDraft.canTrim(duration: playback.duration) else { return }
        draft = TrimDraft(duration: playback.duration, saved: savedTrim?.range)
    }

    // MARK: Top bar

    /// Close and volume on the left; on the right, room for the compression button (JUN-50), hidden until it ships.
    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(Format.size(item.bytes))
                    .font(.footnote.weight(.semibold))
                // Short, to fit between the buttons on either side.
                Text(Format.shortDay(item.date))
                    .font(.footnote)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.size(item.bytes)), \(Format.day(item.date))")
            HStack(spacing: DS.Spacing.s) {
                FrostedIconButton(systemImage: "xmark", accessibilityLabel: "Close") { requestExit(.close) }
                FrostedIconButton(systemImage: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  accessibilityLabel: playback.isMuted ? "Unmute" : "Mute", action: playback.toggleMute)
                    .accessibilityIdentifier("video.volume")
                Spacer(minLength: DS.Spacing.xs)
                // Compression's place (JUN-50). Kept in the layout so adding it doesn't move anything.
                FrostedIconButton(systemImage: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Compress") {}
                    .hidden()
                    .accessibilityHidden(true)
            }
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
            if let draft, draft.isTrimmed || draft.hasUnsavedChanges {
                trimSummary(draft)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            // One flat bar, as in Photos: the play button and the strip at the same height, side by side.
            HStack(spacing: 0) {
                Button(action: playback.togglePlay) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(TrimStrip.glyph(isTrimmed: isTrimmed))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: DS.Tap.minimum + DS.Spacing.xs, maxHeight: .infinity)
                        .background(TrimStrip.fill(isTrimmed: isTrimmed), in: UnevenRoundedRectangle(
                            topLeadingRadius: DS.Trim.cornerRadius, bottomLeadingRadius: DS.Trim.cornerRadius, style: .continuous
                        ))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!playback.isReady)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                // Above the strip, so the start handle's touch area, which reaches outward, never takes its taps.
                .zIndex(1)
                Rectangle()
                    .fill(.black)
                    .frame(width: 1)
                    .accessibilityHidden(true)
                TrimStrip(playback: playback, draft: $draft)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: draft?.isTrimmed)
        .animation(reduceMotion ? nil : DS.Motion.calm, value: hasUnsavedTrim)
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// "1:42 · 380 MB → 0:12 · ~45 MB", then "saves ~335 MB" under it, with Reset and Trim beside them
    /// once the handles differ from what's saved.
    private func trimSummary(_ draft: TrimDraft) -> some View {
        HStack(spacing: DS.Spacing.s) {
            let lines = Self.summary(draft, bytes: item.bytes)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(lines.change)
                    .font(.footnote.weight(.semibold))
                if let saves = lines.saves {
                    Text(saves)
                        .font(.subheadline.weight(.bold))
                }
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([lines.change, lines.saves].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("video.trimSummary")
            if draft.hasUnsavedChanges {
                Button("Reset") { self.draft?.reset() }
                    .buttonStyle(TrimButtonStyle(isPrimary: false))
                    .accessibilityIdentifier("video.trimReset")
                Button(draft.result == nil ? "Save" : "Trim", action: saveTrim)
                    .buttonStyle(TrimButtonStyle(isPrimary: true))
                    .accessibilityHint(draft.result == nil ? "Keeps the whole video and removes its trim" : "Queues the trim in the bin")
                    .accessibilityIdentifier("video.trimSave")
            }
        }
    }

    /// What the selection keeps, "0:08 · 1.23 GB → 0:05 · ~752 MB", and what it saves, "saves ~476 MB".
    /// The new size is the original's times the kept fraction.
    static func summary(_ draft: TrimDraft, bytes: Int64) -> (change: String, saves: String?) {
        guard let trim = draft.result else { return ("Whole video · removes the trim", nil) }
        let original = "\(Format.duration(draft.duration)) · \(Format.size(bytes))"
        let trimmed = "\(Format.duration(trim.range.length)) · ~\(Format.size(trim.estimatedBytes(from: bytes)))"
        return ("\(original) → \(trimmed)", "saves ~\(Format.size(trim.savedBytes(from: bytes)))")
    }
}

/// A round frosted button over the video: close, volume, and later compression.
private struct FrostedIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DS.Tap.minimum, height: DS.Tap.minimum)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Reset and Trim beside the trim summary: a frosted capsule, or brick for Trim, the space it clears.
private struct TrimButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.m)
            .frame(minHeight: DS.Tap.minimum)
            .background(isPrimary ? AnyShapeStyle(DS.Palette.brick) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(DS.Motion.calm, value: configuration.isPressed)
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
    private(set) var isMuted = false
    /// Stills across the clip for the trim strip, in order. Empty until they're made.
    private(set) var frames: [UIImage] = []
    /// While set, playback stays inside it: reaching its end goes back to its start and carries on.
    private(set) var loopRange: TrimRange?
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
        frames = await Self.frames(of: playerItem.asset, duration: duration, count: Self.frameCount)
    }

    /// How many stills the trim strip shows.
    static let frameCount = 12

    /// Evenly spaced stills, small, as quickly as the decoder gives them. Off the main actor, like the size.
    private nonisolated static func frames(of asset: AVAsset, duration: TimeInterval, count: Int) async -> [UIImage] {
        guard duration > 0, count > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        // Any nearby frame will do for a thumbnail, and it's much faster than an exact one.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [UIImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(UIImage(cgImage: image)) }
        }
        return images
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    /// Plays only `range`, on a loop; nil plays the whole clip again. Starts the selection over when
    /// the playhead is outside it.
    func setLoop(_ range: TrimRange?) {
        loopRange = range
        guard let range else { return }
        if currentTime < range.start || currentTime > range.end { seek(to: range.start) }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        if let loopRange, currentTime < loopRange.start || currentTime >= loopRange.end - 0.05 {
            seek(to: loopRange.start)
        } else if duration > 0, currentTime >= duration - 0.05 {
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

    /// `seconds` in, clamped to the clip.
    func scrub(toTime seconds: TimeInterval) {
        seek(to: min(max(seconds, 0), duration))
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
                if let loop = self.loopRange, self.isPlaying, time.seconds >= loop.end { self.seek(to: loop.start) }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A selection that runs to the clip's end loops from here too.
                if let loop = self.loopRange {
                    self.seek(to: loop.start)
                    self.player.play()
                    return
                }
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
#Preview("Trimmable") {
    VideoPreviewView(item: PreviewSamples.video, onTrim: { _ in })
}

#Preview("Pending trim") {
    VideoPreviewView(item: PreviewSamples.video,
                     savedTrim: PendingTrim(range: TrimRange(start: 1, end: 5), originalDuration: 8), onTrim: { _ in })
}

#Preview("Seek bar only") {
    VideoPreviewView(item: PreviewSamples.video)
}

#Preview("XXL") {
    VideoPreviewView(item: PreviewSamples.video, onTrim: { _ in })
        .dynamicTypeSize(.xxLarge)
}
#endif
