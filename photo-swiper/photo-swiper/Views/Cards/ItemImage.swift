import SwiftUI

/// Fills (or, with `.fit`, fits) its frame with an item's image. The single place an
/// `ImageReference` becomes pixels, so a PhotoKit-backed loader only needs to change here.
struct ItemImage: View {
    let reference: ImageReference
    var contentMode: ContentMode = .fill
    /// The image's own size once known, for laying out around the picture rather than the frame.
    var onImageSize: (CGSize) -> Void = { _ in }

    init(_ reference: ImageReference, contentMode: ContentMode = .fill, onImageSize: @escaping (CGSize) -> Void = { _ in }) {
        self.reference = reference
        self.contentMode = contentMode
        self.onImageSize = onImageSize
    }

    var body: some View {
        DS.Palette.muted
            .overlay {
                switch reference {
                case .bundled(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .onAppear {
                            if let size = UIImage(named: name)?.size { onImageSize(size) }
                        }
                case .photoKit(let id):
                    PhotoKitImage(id: id, contentMode: contentMode, onImageSize: onImageSize)
                }
            }
            .clipped()
            // `clipped()` only clips drawing; without this a tall fill steals taps above the card.
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

/// Loads a library image sized to this view. Shows nothing (the muted fill) until the first,
/// possibly low-quality, image arrives; never blocks interaction.
private struct PhotoKitImage: View {
    private struct Request: Equatable {
        let id: String
        let pixelSize: CGSize
    }

    let id: String
    let contentMode: ContentMode
    let onImageSize: (CGSize) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var size = CGSize.zero
    @State private var image: UIImage?
    @State private var loadedID: String?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .task(id: Request(id: id, pixelSize: ThumbnailPipeline.pixelSize(for: size, scale: displayScale))) {
                guard size != .zero else { return }
                if loadedID != id {
                    image = nil
                    loadedID = id
                }
                let pixelSize = ThumbnailPipeline.pixelSize(for: size, scale: displayScale)
                for await next in ThumbnailPipeline.shared.images(for: id, pixelSize: pixelSize) {
                    image = next
                    onImageSize(next.size)
                }
            }
    }
}

#Preview {
    HStack {
        ItemImage(.bundled("photo-sunset"))
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile))
        ItemImage(.bundled("similar-a-1"))
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb))
    }
    .padding()
}
