import SwiftUI

/// Full-bleed single photo with date, place, size, and an optional review flag.
struct PhotoCardView: View {
    let item: LibraryItem
    var onOpen: () -> Void = {}

    private var isBlurry: Bool { item.reviewFlag == .blurry }

    var body: some View {
        ItemImage(item.image)
            .blur(radius: isBlurry ? 10 : 0, opaque: true)
            .overlay { BottomScrim() }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .topLeading) {
                if let flag = item.reviewFlag {
                    Chip(text: flag.label, systemImage: "exclamationmark.circle")
                        .softShadow()
                        .padding(18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .cardShadow()
            .onTapGesture(perform: onOpen)
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
        if let flag = item.reviewFlag { parts.insert(flag.label, at: 1) }
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

#Preview("Blurry") {
    PhotoCardView(item: PreviewSamples.blurryPhoto)
        .padding(14)
        .background(DS.Palette.paper)
}

#Preview("Plain") {
    PhotoCardView(item: PreviewSamples.plainPhoto)
        .padding(14)
        .background(DS.Palette.paper)
}
