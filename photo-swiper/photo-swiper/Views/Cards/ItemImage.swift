import SwiftUI

/// Fills its frame with an item's image. The single place an `ImageReference` becomes pixels,
/// so a PhotoKit-backed loader only needs to change here.
struct ItemImage: View {
    let reference: ImageReference

    init(_ reference: ImageReference) {
        self.reference = reference
    }

    var body: some View {
        DS.Palette.muted
            .overlay {
                switch reference {
                case .bundled(let name):
                    Image(name)
                        .resizable()
                        .scaledToFill()
                case .photoKit(let id):
                    PhotoKitImage(id: id)
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
                        .scaledToFill()
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
