import SwiftUI

/// Full-bleed single photo with date, place, and size, and a Share button when sharing is on (JUN-8).
struct PhotoCardView: View {
    let item: LibraryItem
    var onOpen: () -> Void = {}
    /// The Share button's state; nil shows none.
    var share: ShareButtonState?
    var onShare: () -> Void = {}

    var body: some View {
        ItemImage(item.image)
            .overlay { BottomScrim() }
            .overlay {
                CardCenterButton(accessibilityLabel: "View full screen", action: onOpen)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .cardShareButton(share, action: onShare)
            .rankDebugBadge(for: item)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .cardShadow()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "View full screen", onOpen)
            .cardShareAction(share, action: onShare)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(Format.day(item.date))
                .dsSerif(28, relativeTo: .title)
            HStack(spacing: DS.Spacing.xs) {
                Text([item.location, Format.size(item.bytes)].compactMap { $0 }.joined(separator: " · "))
                if item.isFavorite {
                    Image(systemName: "heart.fill").imageScale(.small)
                }
            }
            .font(.subheadline)
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.leading, DS.Spacing.l)
        .padding(.trailing, share == nil ? DS.Spacing.l : CardShareButton.captionClearance)
        .padding(.bottom, DS.Spacing.l)
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
                .init(color: DS.Palette.scrim.opacity(0.85), location: 1),
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
        .padding(DS.Spacing.cardInset)
        .paperBackground()
}

#Preview("Plain") {
    PhotoCardView(item: PreviewSamples.plainPhoto)
        .padding(DS.Spacing.cardInset)
        .paperBackground()
}

#Preview("Share") {
    PhotoCardView(item: PreviewSamples.plainPhoto, share: .ready)
        .padding(DS.Spacing.cardInset)
        .paperBackground()
}

#Preview("Share, large text") {
    PhotoCardView(item: PreviewSamples.plainPhoto, share: .preparing)
        .padding(DS.Spacing.cardInset)
        .paperBackground()
        .dynamicTypeSize(.xxLarge)
}
#endif
