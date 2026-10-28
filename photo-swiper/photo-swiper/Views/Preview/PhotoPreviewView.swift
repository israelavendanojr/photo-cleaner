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
    @State private var zoom = ZoomTransform()
    /// The screen the photo is fitted into.
    @State private var size = CGSize.zero
    @State private var imageSize = CGSize.zero
    @State private var swipe = PreviewDrag()

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
                .zoomable($zoom, content: photoSize, container: size, swipe: swipe, onSwipe: finish) {
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

#if DEBUG
#Preview {
    PhotoPreviewView(item: PreviewSamples.blurryPhoto)
}
#endif
