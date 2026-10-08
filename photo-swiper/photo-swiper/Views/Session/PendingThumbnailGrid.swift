import SwiftUI

/// Eight-column grid of everything about to be cleared, collapsing overflow into "+N".
struct PendingThumbnailGrid: View {
    let items: [LibraryItem]
    var maxTiles = 24

    private var shown: ArraySlice<LibraryItem> {
        items.count > maxTiles ? items.prefix(maxTiles - 1) : items.prefix(maxTiles)
    }
    private var overflow: Int { items.count - shown.count }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(shown) { item in
                tile { ItemImage(item.image) }
            }
            if overflow > 0 {
                tile {
                    DS.Palette.ink.overlay {
                        Text("+\(overflow)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(items.count) photos to clear")
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(content: content)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    PendingThumbnailGrid(items: Array(PreviewSamples.session.items.prefix(37)))
        .padding(26)
        .background(DS.Palette.paper)
}
