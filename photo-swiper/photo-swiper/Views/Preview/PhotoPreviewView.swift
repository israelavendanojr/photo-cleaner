import AVFoundation
import Photos
import SwiftUI

/// Full-screen view of a photo card, with pinch and double-tap zoom for checking sharpness.
///
/// Swiping left, right, or up decides like on the card; swiping down just closes. The card's
/// blur for flagged photos is dropped here, since this is where you judge whether it's blurry.
///
/// A Live Photo plays its motion while pressed and held, like Photos (JUN-105). Only then does the hold
/// gesture join in, so a plain photo's taps behave as before.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    /// Overlay text for each direction.
    var label: (SwipeDirection) -> String = { _ in "" }
    /// Called once a decision swipe has flown the photo off. The caller closes the preview.
    var onDecide: (SwipeDirection) -> Void = { _ in }

    @State private var showsChrome = true
    @State private var zoom = ZoomTransform()
    /// The screen the photo is fitted into.
    @State private var size = CGSize.zero
    @State private var imageSize = CGSize.zero
    @State private var swipe = PreviewDrag()
    /// Known once `vm.isLivePhoto` answers; false until then.
    @State private var isLive = false
    /// The still and its motion, once loaded. Nil while loading, or if it couldn't be.
    @State private var livePhoto: PHLivePhoto?
    @State private var liveLoadFailed = false
    @State private var isHoldingLive = false
    @State private var isPlayingLive = false
    #if DEBUG
    /// How many times the motion has started, for UI tests, which can't look while a press is held.
    @State private var livePlayCount = 0
    #endif

    var body: some View {
        ZStack {
            DS.Palette.muted.opacity(swipe.backdropOpacity).ignoresSafeArea()
            // Gestures cover the whole screen; only the photo itself moves, so the backdrop
            // around a wide or tall photo stays put.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .overlay { photo }
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                .zoomable($zoom, content: photoSize, container: size, swipe: swipe, onSwipe: finish,
                          onHold: liveHold) {
                    withAnimation(DS.Motion.calm) { showsChrome.toggle() }
                }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("photoPreview")
                .accessibilityActions {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        Button(label(direction)) { decide(direction) }
                    }
                    // No holding under VoiceOver: it plays once through.
                    if livePhoto != nil {
                        Button("Play Live Photo", action: startLive)
                    }
                }
        }
        .overlay(alignment: .top) {
            if isLiveLoading {
                loadingPill
                    .padding(.top, DS.Preview.pillTop)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if showsChrome {
                topBar
                    .opacity(swipe.chromeOpacity)
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showsChrome)
        .presentationBackground(.clear)
        .task { await loadLive() }
        #if DEBUG
        .overlay(alignment: .bottom) { LivePlaybackMarker(count: livePlayCount) }
        #endif
    }

    private var photo: some View {
        ItemImage(item.image, contentMode: .fit) { imageSize = $0 }
            .frame(width: photoSize.width, height: photoSize.height)
            .overlay {
                // Over the still, at the same size, and shown only while playing: at rest the still is sharper.
                if let livePhoto {
                    LivePhotoPlayer(livePhoto: livePhoto, isPlaying: $isPlayingLive)
                        .opacity(isPlayingLive ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(zoom.scale)
            .offset(zoom.offset)
            .overlay { SwipeOverlay(offset: swipe.decideOffset, label: label) }
            .scaleEffect(swipe.contentScale)
            .rotationEffect(.degrees(swipe.rotation))
            .offset(swipe.offset)
    }

    /// The photo fitted to the screen. The whole screen until the image's size is known.
    private var photoSize: CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return size }
        return AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: size)).size
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

    // MARK: Live Photo

    /// A hold that's waiting for the motion to download.
    private var isLiveLoading: Bool { isHoldingLive && livePhoto == nil && !liveLoadFailed }

    private func loadLive() async {
        isLive = await vm.isLivePhoto(item)
        guard isLive else { return }
        // The screen's longer side in pixels; a phone-sized guess if it isn't measured yet.
        let side = size == .zero ? 2_048 : max(size.width, size.height) * displayScale
        livePhoto = await LivePhotoSource.livePhoto(for: item, targetSize: CGSize(width: side, height: side))
        guard !Task.isCancelled else { return }
        // It can't load (iCloud unreachable): the still stays, and holding does nothing more.
        withAnimation(DS.Motion.calm) { liveLoadFailed = livePhoto == nil }
        if isHoldingLive { startLive() }
    }

    /// Holding means something only for a Live Photo; otherwise a long press stays an ordinary touch.
    private var liveHold: ((Bool) -> Void)? {
        guard isLive else { return nil }
        return { isDown in holdLive(isDown) }
    }

    private func holdLive(_ isDown: Bool) {
        withAnimation(DS.Motion.calm) { isHoldingLive = isDown }
        if isDown { startLive() } else { isPlayingLive = false }
    }

    private func startLive() {
        guard livePhoto != nil, !isPlayingLive else { return }
        // Ambient follows the silent switch. The full-screen video sets its own category when it loads.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        isPlayingLive = true
        Haptics.advance()
        #if DEBUG
        livePlayCount += 1
        #endif
    }

    /// "Loading Live Photo", with a spinner, while a hold waits on iCloud.
    private var loadingPill: some View {
        HStack(spacing: DS.Spacing.xs) {
            ProgressView()
                .tint(.white)
                .controlSize(.small)
            Chip(text: "Loading Live Photo", style: .frosted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Live Photo")
        .accessibilityIdentifier("photo.liveLoading")
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
            if isLive {
                Chip(text: "LIVE", systemImage: "livephoto", style: .frosted, size: .footnote)
                    .fixedSize()
                    .accessibilityLabel("Live Photo")
                    .accessibilityIdentifier("photo.liveChip")
            }
            Spacer(minLength: DS.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text([Format.size(item.bytes), item.location].compactMap { $0 }.joined(separator: " · "))
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

    private var accessibilityText: String {
        [isLive ? "Live Photo" : "Photo", Format.day(item.date), item.location].compactMap { $0 }.joined(separator: ", ")
    }
}

#if DEBUG
/// Tells UI tests how many times a Live Photo started playing. Only with the mock library.
private struct LivePlaybackMarker: View {
    let count: Int

    var body: some View {
        if LibraryServices.usesMock {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("\(count)")
                .accessibilityIdentifier("photo.livePlayCount")
        }
    }
}

#Preview("Photo") {
    PhotoPreviewView(item: PreviewSamples.blurryPhoto)
        .environment(FeedViewModel.mock())
}

#Preview("Live Photo") {
    PhotoPreviewView(item: PreviewSamples.livePhoto)
        .environment(FeedViewModel.mock())
}

#Preview("Live Photo, XXL") {
    PhotoPreviewView(item: PreviewSamples.livePhoto)
        .environment(FeedViewModel.mock())
        .dynamicTypeSize(.xxLarge)
}
#endif
