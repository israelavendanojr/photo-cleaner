import AVFoundation
import SwiftUI

/// Full-screen playback for a video, laid out after Photos' video editor: close and volume at the top
/// left, compression at the top right, the video in the middle, and at the bottom a play button beside
/// the trim strip (`TrimStrip`).
///
/// The strip is the timeline. Moving either handle plays the selection on a loop. The compression button
/// opens `CompressionPopup`: choosing a level previews a few seconds of it (`CompressionPreviewer`) over
/// the video, and pressing and holding the video shows the original meanwhile; Apply keeps the level.
/// Once trimmed or compressed, a line shows what the edit saves, with Reset and Save. Save hands the
/// edit to `onEdit`; nothing is exported until the bin is confirmed. Leaving with unsaved changes
/// (close, a swipe down, a decision swipe) asks first: save, discard, or keep editing (`EditDraft`).
/// Without `onEdit`, or for slow-motion and Cinematic videos, nothing can be edited and the strip is a
/// plain seek bar; it's one too for clips too short to trim, or with trimming off.
///
/// Pinch and double-tap zoom like photos. Swiping the video left, right, or up decides like on the card;
/// swiping down closes. While zoomed, one finger pans instead. Pressing and holding plays at 2x until the
/// finger lifts (or shows the original, while a preview plays); VoiceOver gets actions for both instead.
struct VideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The system's appearance. The viewer forces dark for itself; its paywall follows the system.
    @Environment(\.colorScheme) private var systemColorScheme
    let item: LibraryItem
    /// Overlay text for each direction.
    var label: (SwipeDirection) -> String = { _ in "" }
    /// Called once a decision swipe has flown the video off. The caller closes the preview.
    var onDecide: (SwipeDirection) -> Void = { _ in }
    /// The edit waiting for this video, if any. The handles open where its trim left them.
    var savedEdit: PendingEdit?
    /// Called with the edit to save, or nil to keep the video as it is (a saved trim dragged back to the
    /// ends, with no compression level). The caller closes the preview. Nil offers no editing.
    var onEdit: ((PendingEdit?) -> Void)?
    /// Whether trimming and compressing are offered (each is a feature that can be off), and the levels'
    /// settings for the estimates and previews.
    var options = VideoEditOptions()

    @State private var playback = VideoPlayback()
    @State private var showsControls = true
    @State private var swipe = PreviewDrag()
    @State private var zoom = ZoomTransform()
    /// The screen the video is fitted into.
    @State private var size = CGSize.zero
    @State private var posterSize = CGSize.zero
    /// The edit, once the clip's length is known. Nil while loading, and when nothing can be edited.
    @State private var draft: EditDraft?
    /// A way out the user took with unsaved changes, held while the dialog asks about it.
    @State private var pendingExit: Exit?
    /// The clip's sizes and bitrates, for the compression estimates. Nil until read.
    @State private var source: VideoSourceInfo?
    @State private var previewer = CompressionPreviewer()
    @State private var sample = SampleLoop()
    @State private var isChoosingLevel = false
    /// The level highlighted in the popup, previewed but not yet applied.
    @State private var levelChoice: CompressionLevel?
    /// The original shows in place of the preview while the video is held.
    @State private var isComparing = false
    @State private var wasPlayingBeforeChoosing = false
    /// Saving a locked trim or applying a locked compression level opens the paywall here, over the viewer.
    @State private var isUnlockPresented = false

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
                    // A tap outside the compression popup closes it, as outside a sheet would.
                    if isChoosingLevel { return closeLevels() }
                    withAnimation(DS.Motion.calm) { showsControls.toggle() }
                }
                .accessibilityActions {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { requestExit(.decide(direction)) }
                    }
                    if previewer.sampleURL != nil {
                        Button(isComparing ? "Show the preview" : "Show the original") { compare(!isComparing) }
                    } else if playback.isReady {
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
                    .padding(.top, DS.Preview.pillTop)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                    .accessibilityLabel("Playing at 2x speed")
                    .accessibilityIdentifier("video.speedPill")
            }
        }
        .overlay(alignment: .top) {
            if isChoosingLevel, let level = previewer.level {
                previewLabel(level)
                    // Below the top bar, like the 2x pill.
                    .padding(.top, DS.Preview.pillTop)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showsControls {
                topBar
                    .opacity(swipe.chromeOpacity)
                    .accessibilityHidden(isChoosingLevel)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showsControls {
                controls
                    .opacity(swipe.chromeOpacity)
                    .accessibilityHidden(isChoosingLevel)
                    .transition(.opacity)
            }
        }
        .confirmationDialog("Save changes?", isPresented: isAskingToLeave, titleVisibility: .visible, presenting: pendingExit) { exit in
            Button("Save changes", action: saveEdit)
            Button("Discard", role: .destructive) { leave(exit) }
            Button("Keep editing", role: .cancel) {}
        } message: { _ in
            Text("You changed this video's trim or compression. Nothing changes in your library until you clear the bin.")
        }
        // Over the viewer, since RootView's sheets can't show above a full-screen cover. Closing it
        // leaves the edit as it was, so the user can keep previewing or discard it.
        .sheet(isPresented: $isUnlockPresented) {
            UnlockSheet()
                .environment(\.colorScheme, systemColorScheme)
                .presentationDragIndicator(.visible)
                .presentationBackground { PaperBackground() }
                .presentationCornerRadius(DS.Radius.card)
        }
        .overlay {
            // No scrim: the video stays live around the popup, for the preview and press-and-hold.
            if isChoosingLevel {
                CompressionPopup(trimmedBytes: trimmedBytes, estimates: estimates, choice: levelChoice,
                                 onChoose: chooseLevel, onApply: applyLevel, onClose: closeLevels)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: isChoosingLevel)
        .onChange(of: isChoosingLevel) { _, choosing in if !choosing { endChoosingLevel() } }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .task { await playback.load(item) }
        .task(id: playback.isReady) { await readSource() }
        .onChange(of: playback.isReady) { setUpEdit() }
        .onChange(of: draft?.trim) { playback.setLoop(trimLoop) }
        // Samples are made inside the trim; a new trim needs new ones.
        .onChange(of: draft?.range) { previewer.clear() }
        .onChange(of: previewer.sampleURL) { _, url in
            isComparing = false
            sample.play(url, muted: playback.isMuted)
        }
        .onChange(of: playback.isMuted) { _, muted in sample.player.isMuted = muted }
        .onDisappear {
            playback.stop()
            sample.play(nil, muted: true)
            previewer.clear()
        }
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
            // The level's sample over the original, the same size; holding the video uncovers the original.
            if previewer.sampleURL != nil, !isComparing {
                PlayerLayerView(player: sample.player)
                    .accessibilityHidden(true)
            }
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
        if previewer.sampleURL != nil || isComparing { return compare(isDown) }
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
        // While the level popup is up, the video only previews: no closing or deciding underneath it.
        guard !isChoosingLevel else { return swipe.cancel() }
        switch outcome {
        case .dismiss: requestExit(.close)
        case .decide(let direction): requestExit(.decide(direction))
        }
    }

    // MARK: Leaving

    private var hasUnsavedEdit: Bool { draft?.hasUnsavedChanges ?? false }

    private var isAskingToLeave: Binding<Bool> {
        Binding(get: { pendingExit != nil }, set: { if !$0 { pendingExit = nil } })
    }

    /// Every way out comes through here. With the handles moved, the video settles back and the dialog asks.
    private func requestExit(_ exit: Exit) {
        guard hasUnsavedEdit else { return leave(exit) }
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

    /// Hands the edit to the caller, which closes the viewer.
    private func saveEdit() {
        pendingExit = nil
        guard let draft, draft.hasUnsavedChanges else { return }
        let edit = draft.result(compressedBytes: compressedBytes)
        if options.needsUnlock(edit) {
            isUnlockPresented = true
            return
        }
        onEdit?(edit)
    }

    /// The edit once the clip's length is known, from what's saved. None without `onEdit`, for slow-motion
    /// and Cinematic videos, or when there's nothing left to offer (too short to trim, compression off).
    private func setUpEdit() {
        guard onEdit != nil, draft == nil, playback.isReady, VideoSource.canEdit(item) else { return }
        let edit = EditDraft(duration: playback.duration, saved: savedEdit, canTrim: options.canTrim)
        guard edit.trim != nil || options.canCompress else { return }
        draft = edit
    }

    /// The handles' selection, which plays on a loop.
    private var trimLoop: TrimRange? {
        draft?.trim.flatMap { $0.isTrimmed ? $0.range : nil }
    }

    /// The strip edits only the trim.
    private var trimBinding: Binding<TrimDraft?> {
        Binding(get: { draft?.trim }, set: { draft?.trim = $0 })
    }

    // MARK: Compression

    private func readSource() async {
        guard playback.isReady, source == nil, let playing = playback.asset else { return }
        // An asset is immutable and loads its properties from any thread, so reading it off the main actor is safe.
        nonisolated(unsafe) let asset = playing
        source = try? await VideoSourceInfo.load(from: asset, fallbackBytes: item.bytes)
    }

    /// The video's size after the draft's trim, which None keeps.
    private var trimmedBytes: Int64 {
        PendingEdit(range: draft?.range, originalDuration: draft?.duration ?? 0).estimatedBytes(from: item.bytes)
    }

    /// Each level's estimate after the draft's trim. Nil until the clip's tracks are read.
    private var estimates: [CompressionLevel: CompressionEstimate]? {
        guard let source, let draft else { return nil }
        let trimmed = PendingEdit(range: draft.range, originalDuration: draft.duration)
        return Dictionary(uniqueKeysWithValues: CompressionLevel.allCases.map {
            ($0, CompressionEstimate.make($0, levels: options.levels, source: source, originalBytes: item.bytes, edit: trimmed))
        })
    }

    /// The chosen level's estimate, saved with the edit.
    private var compressedBytes: Int64? {
        draft?.compression.flatMap { estimates?[$0]?.compressedBytes }
    }

    private func openLevels() {
        guard draft != nil else { return }
        levelChoice = draft?.compression
        wasPlayingBeforeChoosing = playback.isPlaying
        setBoost(false, restoring: false)
        playback.pause()
        isChoosingLevel = true
        preview(levelChoice)
    }

    private func chooseLevel(_ level: CompressionLevel?) {
        levelChoice = level
        Haptics.advance()
        preview(level)
    }

    private func applyLevel() {
        if options.needsUnlock(level: levelChoice) {
            isUnlockPresented = true
            return
        }
        draft?.setCompression(levelChoice)
        isChoosingLevel = false
    }

    /// Closes the popup without applying: the level stays as it was.
    private func closeLevels() {
        isChoosingLevel = false
    }

    /// Back to the plain video: the sample stops (its encode too, if it's running), and playback picks up
    /// where it was.
    private func endChoosingLevel() {
        if isComparing { compare(false) }
        previewer.show(nil, asset: nil, settings: nil, around: 0, within: TrimRange(start: 0, end: 0))
        playback.setLoop(trimLoop)
        if wasPlayingBeforeChoosing { playback.play() }
    }

    /// Encodes (or reuses) `level`'s sample around the playhead, inside the trim.
    private func preview(_ level: CompressionLevel?) {
        let settings = level.flatMap { level in source.map { CompressionSettings.resolve(level, levels: options.levels, source: $0) } }
        let range = draft?.range ?? TrimRange(start: 0, end: playback.duration)
        previewer.show(level, asset: playback.asset, settings: settings, around: playback.currentTime, within: range)
    }

    /// Holding the video shows the original over the same seconds as the sample; letting go goes back.
    private func compare(_ showsOriginal: Bool) {
        guard isComparing != showsOriginal else { return }
        if showsOriginal {
            guard let window = previewer.window else { return }
            sample.player.pause()
            playback.setLoop(window)
            playback.scrub(toTime: window.start + sample.currentTime)
            playback.play()
        } else {
            playback.pause()
            playback.setLoop(trimLoop)
            sample.player.play()
        }
        isComparing = showsOriginal
    }

    /// "Preview · Balanced", with a spinner while its sample encodes, or "Original" while held.
    private func previewLabel(_ level: CompressionLevel) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if previewer.isEncoding {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
            }
            Chip(text: isComparing ? "Original" : "Preview · \(level.title)", style: .frosted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(previewer.isEncoding ? "Making the \(level.title) preview" : (isComparing ? "Showing the original" : "Previewing \(level.title)"))
        .accessibilityIdentifier("video.previewLabel")
    }

    // MARK: Top bar

    /// Close and volume on the left; compression on the right. Its place is kept when it isn't offered,
    /// so nothing moves.
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
                if options.canCompress, draft != nil {
                    FrostedIconButton(systemImage: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Compress",
                                      isActive: draft?.compression != nil, action: openLevels)
                        .accessibilityValue(draft?.compression?.title ?? "None")
                        .accessibilityIdentifier("video.compress")
                } else {
                    FrostedIconButton(systemImage: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Compress") {}
                        .hidden()
                        .accessibilityHidden(true)
                }
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
            if let draft, draft.isEdited || draft.hasUnsavedChanges {
                editSummary(draft)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            // One flat bar, as in Photos: the play button and the strip at the same height, side by side.
            HStack(spacing: 0) {
                Button(action: playback.togglePlay) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: DS.Tap.minimum + DS.Spacing.xs, maxHeight: .infinity)
                        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(
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
                TrimStrip(playback: playback, draft: trimBinding)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: draft?.isEdited)
        .animation(reduceMotion ? nil : DS.Motion.calm, value: hasUnsavedEdit)
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.xxl)
        .padding(.bottom, DS.Spacing.m)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// "1:42 · 380 MB → 0:12 · ~45 MB", then "saves ~335 MB" under it, with Reset and Save beside them
    /// once the edit differs from what's saved.
    private func editSummary(_ draft: EditDraft) -> some View {
        HStack(spacing: DS.Spacing.s) {
            let lines = Self.summary(draft, bytes: item.bytes, compressedBytes: compressedBytes)
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
                let removes = draft.result(compressedBytes: compressedBytes) == nil
                Button("Save", action: saveEdit)
                    .buttonStyle(TrimButtonStyle(isPrimary: true))
                    .accessibilityHint(removes ? "Keeps the original video and removes its edit" : "Queues the edit in the bin")
                    .accessibilityIdentifier("video.trimSave")
            }
        }
    }

    /// What the edit keeps, "0:08 · 1.23 GB → 0:05 · ~752 MB", and what it saves, "saves ~476 MB", trim and
    /// compression together. A trim alone is the original's size times the kept fraction; a level uses
    /// `compressedBytes`, its estimate after the trim.
    static func summary(_ draft: EditDraft, bytes: Int64, compressedBytes: Int64?) -> (change: String, saves: String?) {
        guard let edit = draft.result(compressedBytes: compressedBytes) else { return ("Original video · removes the edit", nil) }
        let original = "\(Format.duration(draft.duration)) · \(Format.size(bytes))"
        let edited = "\(Format.duration(edit.newDuration)) · ~\(Format.size(edit.estimatedBytes(from: bytes)))"
        return ("\(original) → \(edited)", "saves ~\(Format.size(edit.savedBytes(from: bytes)))")
    }
}

/// A round frosted button over the video: close, volume, compression, and the compression popup's close.
/// Active (a level set) fills it brick, as trimming turns the strip brick: space to clear.
struct FrostedIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DS.Tap.minimum, height: DS.Tap.minimum)
                .background(isActive ? AnyShapeStyle(DS.Palette.brickFill) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Reset and Save beside the edit summary, and the compression popup's Apply: a frosted capsule, or brick
/// for the primary one, the space it clears.
struct TrimButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.m)
            .frame(minHeight: DS.Tap.minimum)
            .background(isPrimary ? AnyShapeStyle(DS.Palette.brickFill) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
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
    /// The clip being played, for compression estimates and previews. Nil until loaded.
    @ObservationIgnored private(set) var asset: AVAsset?

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

    /// How long one frame lasts, for telling a Live Photo's key frame from its neighbours. 30 fps until loaded.
    private(set) var frameDuration: TimeInterval = 1.0 / 30

    /// One frame's length in the clip's video track. Off the main actor, like the size.
    private nonisolated static func frameDuration(of asset: AVAsset) async -> TimeInterval? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let frame = try? await track.load(.minFrameDuration), frame.isNumeric, frame.seconds > 0 else { return nil }
        return frame.seconds
    }

    func load(_ item: LibraryItem) async {
        duration = item.duration ?? 0
        guard let playerItem = await VideoSource.playerItem(for: item), !Task.isCancelled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        await prepare(playerItem)
        play()
        frames = await Self.frames(of: playerItem.asset, duration: duration, count: Self.frameCount)
    }

    /// A Live Photo's motion for its frame strip (JUN-106), muted and paused at `time`, the key photo. It
    /// leaves the audio session alone: nothing plays.
    func load(motion url: URL, at time: TimeInterval) async {
        isMuted = true
        player.isMuted = true
        let playerItem = AVPlayerItem(url: url)
        await prepare(playerItem)
        guard !Task.isCancelled else { return }
        seek(to: min(max(time, 0), duration))
        frames = await Self.frames(of: playerItem.asset, duration: duration, count: Self.frameCount)
    }

    private func prepare(_ playerItem: AVPlayerItem) async {
        player.replaceCurrentItem(with: playerItem)
        asset = playerItem.asset
        if let loaded = try? await playerItem.asset.load(.duration), loaded.isNumeric, loaded.seconds > 0 {
            duration = loaded.seconds
        }
        if let size = await Self.uprightSize(of: playerItem.asset) {
            videoSize = size
        }
        if let frame = await Self.frameDuration(of: playerItem.asset) {
            frameDuration = frame
        }
        observe(playerItem)
        isReady = true
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

/// Loops a compression level's sample over the video.
@Observable
@MainActor
final class SampleLoop {
    let player = AVQueuePlayer()
    @ObservationIgnored private var looper: AVPlayerLooper?

    /// Seconds into the sample.
    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    /// Loops the file at `url`, or stops with nil.
    func play(_ url: URL?, muted: Bool) {
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        guard let url else { return }
        player.isMuted = muted
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
}

/// An `AVPlayerLayer` with no system controls, so the preview's own controls are the only ones. The photo
/// viewer shows a Live Photo's chosen frame with it too.
struct PlayerLayerView: UIViewRepresentable {
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
    VideoPreviewView(item: PreviewSamples.video, onEdit: { _ in })
}

#Preview("Pending edit") {
    VideoPreviewView(item: PreviewSamples.video,
                     savedEdit: PendingEdit(range: TrimRange(start: 1, end: 5), originalDuration: 8, compression: .balanced),
                     onEdit: { _ in })
}

#Preview("Seek bar only") {
    VideoPreviewView(item: PreviewSamples.video)
}

#Preview("XXL") {
    VideoPreviewView(item: PreviewSamples.video, onEdit: { _ in })
        .dynamicTypeSize(.xxLarge)
}
#endif
