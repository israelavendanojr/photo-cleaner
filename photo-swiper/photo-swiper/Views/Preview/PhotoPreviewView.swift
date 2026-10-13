import AVFoundation
import SwiftUI

/// Full-screen view of a photo card, with pinch and double-tap zoom for checking sharpness.
///
/// Swiping left, right, or up decides like on the card; swiping down just closes. The card's
/// blur for flagged photos is dropped here, since this is where you judge whether it's blurry.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    /// Overlay text for each direction.
    var label: (SwipeDirection) -> String = { _ in "" }
    /// Called once a decision swipe has flown the photo off. The caller closes the preview.
    var onDecide: (SwipeDirection) -> Void = { _ in }

    @State private var showsChrome = true
    @State private var zoom = ZoomState()
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    /// The screen the photo is fitted into.
    @State private var size = CGSize.zero
    @State private var imageSize = CGSize.zero
    @State private var swipe = PreviewDrag()

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

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
                .gesture(magnify)
                // Alongside the pinch: otherwise a one-finger drag waits for the pinch to fail,
                // which only happens on lift-off, so nothing would follow the finger.
                .simultaneousGesture(drag)
                .onTapGesture(count: 2, coordinateSpace: .local) { toggleZoom(at: $0) }
                .onTapGesture {
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
    }

    private var photo: some View {
        ItemImage(item.image, contentMode: .fit) { imageSize = $0 }
            .frame(width: photoSize.width, height: photoSize.height)
            .scaleEffect(liveScale)
            .offset(liveOffset)
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

    // MARK: Zoom

    private var liveScale: CGFloat {
        min(max(zoom.scale * pinch, 1), Self.maxScale)
    }

    private var liveOffset: CGSize {
        clamped(CGSize(width: zoom.offset.width + pan.width, height: zoom.offset.height + pan.height), scale: liveScale)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                withAnimation(DS.Motion.snapBack) {
                    zoom.scale = min(max(zoom.scale * value.magnification, 1), Self.maxScale)
                    zoom.offset = clamped(zoom.offset, scale: zoom.scale)
                }
            }
    }

    /// Pans while zoomed; at rest, swipes down to close or any other way to decide. Global
    /// coordinates so the image's own offset and scale don't skew the finger's movement.
    private var drag: some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($pan) { value, state, _ in
                if zoom.isZoomed { state = value.translation }
            }
            .onChanged { value in
                guard !zoom.isZoomed else { return }
                if pinch == 1 { swipe.track(value) } else { swipe.cancel() }
            }
            .onEnded { value in
                guard zoom.isZoomed else {
                    switch swipe.end(value) {
                    case .dismiss: dismiss()
                    case .decide(let direction): decide(direction)
                    case nil: break
                    }
                    return
                }
                let moved = CGSize(
                    width: zoom.offset.width + value.translation.width,
                    height: zoom.offset.height + value.translation.height
                )
                withAnimation(DS.Motion.snapBack) { zoom.offset = clamped(moved, scale: zoom.scale) }
            }
    }

    private func decide(_ direction: SwipeDirection) {
        swipe.flyOut(direction) { onDecide(direction) }
    }

    /// Zooms in keeping the tapped point under the finger, or back out to fit.
    private func toggleZoom(at point: CGPoint) {
        withAnimation(DS.Motion.calm) {
            if zoom.isZoomed {
                zoom = ZoomState()
            } else {
                let scale = Self.doubleTapScale
                let target = CGSize(
                    width: (point.x - size.width / 2) * (1 - scale),
                    height: (point.y - size.height / 2) * (1 - scale)
                )
                zoom = ZoomState(scale: scale, offset: clamped(target, scale: scale))
            }
        }
    }

    /// Lets the zoomed photo pan until its edge meets the screen's edge, and keeps it centered
    /// on an axis where it's still smaller than the screen.
    private func clamped(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max((photoSize.width * scale - size.width) / 2, 0)
        let maxY = max((photoSize.height * scale - size.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
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
        ["Photo", Format.day(item.date), item.location].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct ZoomState {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var isZoomed: Bool { scale > 1.01 }
}

#Preview {
    PhotoPreviewView(item: PreviewSamples.blurryPhoto)
}
