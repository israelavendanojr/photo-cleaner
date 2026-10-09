import SwiftUI

/// Full-screen view of a photo card, with pinch and double-tap zoom for checking sharpness.
///
/// Only for looking: decisions still happen on the card once this closes, except from the
/// pending pile, which passes `onKeep` to offer taking the photo back out. The card's blur
/// for flagged photos is dropped here, since this is where you judge whether it's blurry.
struct PhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    /// Shows a "Keep instead" button that calls this and closes.
    var onKeep: (() -> Void)?

    @State private var showsChrome = true
    @State private var zoom = ZoomState()
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    @State private var size = CGSize.zero

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ItemImage(item.image, contentMode: .fit)
                .ignoresSafeArea()
                .scaleEffect(liveScale)
                .offset(liveOffset)
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                .gesture(magnify)
                .gesture(drag, including: zoom.isZoomed ? .all : .subviews)
                .onTapGesture(count: 2, coordinateSpace: .local) { toggleZoom(at: $0) }
                .onTapGesture {
                    withAnimation(DS.Motion.calm) { showsChrome.toggle() }
                }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("photoPreview")
        }
        .overlay(alignment: .top) {
            if showsChrome { topBar.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if showsChrome, let onKeep {
                KeepInsteadButton(onKeep: onKeep)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.top, DS.Spacing.xxl)
                    .padding(.bottom, DS.Spacing.m)
                    .background {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                    }
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showsChrome)
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

    /// Only active while zoomed, so it never fights the image at rest.
    private var drag: some Gesture {
        DragGesture()
            .updating($pan) { value, state, _ in state = value.translation }
            .onEnded { value in
                let moved = CGSize(
                    width: zoom.offset.width + value.translation.width,
                    height: zoom.offset.height + value.translation.height
                )
                withAnimation(DS.Motion.snapBack) { zoom.offset = clamped(moved, scale: zoom.scale) }
            }
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

    /// Keeps the zoomed image covering the screen instead of sliding off an edge.
    private func clamped(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
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

/// White pill on previews opened from the pending pile.
struct KeepInsteadButton: View {
    @Environment(\.dismiss) private var dismiss
    let onKeep: () -> Void

    var body: some View {
        Button {
            onKeep()
            dismiss()
        } label: {
            Text("Keep instead")
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint("Takes this out of the pending pile")
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
