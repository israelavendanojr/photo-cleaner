import SwiftUI

/// A burst of similar shots: the best pick up top, the rest marked to clear.
/// Tapping a shot opens the set one by one there; a thumbnail's corner mark toggles whether it gets cleared.
struct SimilarShotsCardView: View {
    let group: SimilarGroup
    let marked: Set<LibraryItem.ID>
    let onToggle: (LibraryItem.ID) -> Void
    /// Opens the one-by-one review on this shot.
    let onOpen: (LibraryItem.ID) -> Void

    /// Includes the best pick when a partial review chose to delete it.
    private var markedItems: [LibraryItem] { group.items.filter { marked.contains($0.id) } }
    private var totalBytes: Int64 { group.items.reduce(0) { $0 + $1.bytes } }
    private var clearBytes: Int64 { markedItems.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hero
                .padding(.top, DS.Spacing.s)
            Text(group.reason)
                .dsSerif(22, relativeTo: .title3, italic: true)
                .foregroundStyle(DS.Palette.ink)
                .padding(.top, DS.Spacing.s)
            Text("The other \(Format.spelled(group.others.count)) can go.")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .padding(.top, 2)
            thumbnails
                .padding(.top, DS.Spacing.s)
            footer
                .padding(.top, DS.Spacing.l)
        }
        .padding(18)
        .background(DS.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .cardShadow()
    }

    private var header: some View {
        HStack {
            Chip(text: "\(group.items.count) similar shots")
            Spacer(minLength: DS.Spacing.xs)
            Text("\(Format.shortDay(group.best.date)) · \(Format.size(totalBytes))")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .lineLimit(1)
        }
    }

    private var hero: some View {
        ItemImage(group.best.image)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .overlay {
                CardCenterButton(accessibilityLabel: "Go one by one") { onOpen(group.bestID) }
            }
            .overlay(alignment: .topLeading) {
                Chip(text: "Best pick", systemImage: "star.fill", style: .plain)
                    .padding(DS.Spacing.s)
            }
            .overlay(alignment: .topTrailing) {
                if marked.contains(group.bestID) {
                    MarkCircle(isMarked: true)
                        .padding(DS.Spacing.s)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Best pick. \(group.reason)")
            .accessibilityValue(marked.contains(group.bestID) ? "Marked to clear" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("similar.hero")
            .accessibilityAction { onOpen(group.bestID) }
            .accessibilityAction(named: "Go one by one") { onOpen(group.bestID) }
            .rankDebugBadge(for: group)
    }

    private var thumbnails: some View {
        HStack(spacing: 6) {
            ForEach(Array(group.others.enumerated()), id: \.element.id) { offset, item in
                SimilarThumbnail(
                    item: item,
                    isMarked: marked.contains(item.id),
                    number: offset + 2,
                    onOpen: { onOpen(item.id) },
                    onToggle: { onToggle(item.id) }
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Group {
                if markedItems.isEmpty {
                    Text("Nothing marked to clear")
                } else {
                    Text("\(Image(systemName: "arrow.left")) Keep the best, clear \(markedItems.count) · \(Format.size(clearBytes))")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(markedItems.isEmpty ? DS.Palette.secondary : DS.Palette.brick)
            .contentTransition(.numericText())
            Spacer(minLength: DS.Spacing.xs)
            Button { onOpen(group.bestID) } label: {
                Text("Tap to go one by one")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
            .buttonStyle(.plain)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(DS.Motion.calm, value: marked)
    }
}

/// Opens its shot in the review. The corner mark is its own button that toggles clearing.
private struct SimilarThumbnail: View {
    let item: LibraryItem
    let isMarked: Bool
    let number: Int
    let onOpen: () -> Void
    let onToggle: () -> Void

    /// The corner mark's tap target, bigger than the circle drawn.
    private let markHitSize: CGFloat = 30

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ItemImage(item.image)
                        .blur(radius: 1.5, opaque: true)
                        .opacity(isMarked ? 1 : 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Open shot \(number)")
        .overlay(alignment: .topTrailing) {
            Button(action: onToggle) {
                MarkCircle(isMarked: isMarked)
                    .frame(width: markHitSize, height: markHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shot \(number)")
            .accessibilityValue(isMarked ? "Marked to clear" : "Keeping")
            .accessibilityHint("Double tap to toggle")
        }
        .animation(DS.Motion.calm, value: isMarked)
    }
}

/// The corner circle on a shot: a brick cross when marked to clear, an empty ring when kept.
private struct MarkCircle: View {
    let isMarked: Bool

    var body: some View {
        if isMarked {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(DS.Palette.brick, in: Circle())
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .fill(DS.Palette.card.opacity(0.6))
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var marked = Set(PreviewSamples.similarGroup.others.map(\.id))

    SimilarShotsCardView(group: PreviewSamples.similarGroup, marked: marked, onToggle: { id in
        if marked.contains(id) { marked.remove(id) } else { marked.insert(id) }
    }, onOpen: { print("open", $0) })
    .frame(height: 560)
    .padding(14)
    .background(DS.Palette.paper)
}
#endif
