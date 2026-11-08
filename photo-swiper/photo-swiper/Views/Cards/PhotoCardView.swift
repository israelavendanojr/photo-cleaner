import SwiftUI

/// Full-bleed single photo with date, place, and size.
struct PhotoCardView: View {
    let item: LibraryItem
    var onOpen: () -> Void = {}

    var body: some View {
        ItemImage(item.image)
            .overlay { BottomScrim() }
            .overlay {
                CardCenterButton(accessibilityLabel: "View full screen", action: onOpen)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .rankDebugBadge(for: item)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .cardShadow()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "View full screen", onOpen)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.day(item.date))
                .dsSerif(26, relativeTo: .title)
            HStack(spacing: 6) {
                Text([item.location, Format.size(item.bytes)].compactMap { $0 }.joined(separator: " · "))
                if item.isFavorite {
                    Image(systemName: "heart.fill").imageScale(.small)
                }
            }
            .font(.subheadline)
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var accessibilityText: String {
        var parts = ["Photo", Format.day(item.date), item.location, Format.size(item.bytes)].compactMap { $0 }
        if item.isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

/// Darkens the lower third so white captions stay legible.
struct BottomScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.55),
                .init(color: DS.Palette.ink.opacity(0.85), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Flagged") {
    PhotoCardView(item: PreviewSamples.blurryPhoto)
        .padding(14)
        .background(DS.Palette.paper)
}

#Preview("Plain") {
    PhotoCardView(item: PreviewSamples.plainPhoto)
        .padding(14)
        .background(DS.Palette.paper)
}
#endif
