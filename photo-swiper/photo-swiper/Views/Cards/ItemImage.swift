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
                image
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var image: Image {
        switch reference {
        case .bundled(let name): Image(name)
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
