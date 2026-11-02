import SwiftUI

/// The same photo saved more than once: the copy to keep up top, the other copies below with when
/// each was saved. Tapping a copy opens the set one by one there.
struct DuplicatesCardView: View {
    let group: DuplicateGroup
    let marked: Set<LibraryItem.ID>
    /// Opens the one-by-one review on this copy.
    let onOpen: (LibraryItem.ID) -> Void

    /// Copies shown as thumbnails; the rest are summed up on the last tile.
    private static let maxThumbnails = 4

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
            Text(group.others.count == 1 ? "The other copy can go." : "The other \(Format.spelled(group.others.count)) copies can go.")
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
            Chip(text: "\(group.items.count) copies of the same photo")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: DS.Spacing.xs)
            Text(Format.size(totalBytes))
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .lineLimit(1)
        }
    }

    private var hero: some View {
        ItemImage(group.keep.image)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .overlay {
                CardCenterButton(accessibilityLabel: "Go one by one") { onOpen(group.keepID) }
            }
            .overlay(alignment: .topLeading) {
                Chip(text: "Keep", systemImage: "checkmark", style: .plain)
                    .padding(DS.Spacing.s)
            }
            .overlay(alignment: .bottomLeading) {
                Chip(text: "Saved \(Format.shortDay(group.keep.date))", style: .frosted, size: .caption)
                    .padding(DS.Spacing.s)
            }
            .accessibilityElement()
            .accessibilityLabel("Copy to keep, saved \(Format.shortDay(group.keep.date)). \(group.reason)")
            .accessibilityValue(marked.contains(group.keepID) ? "Marked to clear" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("duplicates.hero")
            .accessibilityAction { onOpen(group.keepID) }
            .accessibilityAction(named: "Go one by one") { onOpen(group.keepID) }
    }

    private var thumbnails: some View {
        let others = group.others
        let shown = others.count > Self.maxThumbnails ? Array(others.prefix(Self.maxThumbnails - 1)) : others
        let hidden = others.count - shown.count
        return HStack(alignment: .top, spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { offset, item in
                DuplicateThumbnail(item: item, isMarked: marked.contains(item.id), number: offset + 2) { onOpen(item.id) }
            }
            if hidden > 0, let first = others.dropFirst(shown.count).first {
                Button { onOpen(first.id) } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .background(DS.Palette.paper, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                        .overlay {
                            Text("+\(hidden)")
                                .font(.headline)
                                .foregroundStyle(DS.Palette.secondary)
                        }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("\(hidden) more copies")
            }
            // Keeps tiles thumbnail-sized when there are only one or two.
            ForEach(0..<max(0, 3 - shown.count - (hidden > 0 ? 1 : 0)), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private var footer: some View {
        HStack {
            Group {
                if markedItems.isEmpty {
                    Text("Nothing marked to clear")
                } else {
                    Text("\(Image(systemName: "arrow.left")) Keep one, clear \(markedItems.count) · \(Format.size(clearBytes))")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(markedItems.isEmpty ? DS.Palette.secondary : DS.Palette.brick)
            Spacer(minLength: DS.Spacing.xs)
            Button { onOpen(group.keepID) } label: {
                Text("Tap to go one by one")
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.secondary)
            }
            .buttonStyle(.plain)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// One copy to clear: its image and the day it was saved. Opens the review on it.
private struct DuplicateThumbnail: View {
    let item: LibraryItem
    let isMarked: Bool
    let number: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ItemImage(item.image)
                            .opacity(isMarked ? 1 : 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                Text(Format.shortDay(item.date))
                    .font(.caption)
                    .foregroundStyle(DS.Palette.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Open copy \(number), saved \(Format.shortDay(item.date))")
        .accessibilityValue(isMarked ? "Marked to clear" : "Keeping")
    }
}

#if DEBUG
#Preview {
    let group = PreviewSamples.duplicateGroup
    DuplicatesCardView(group: group, marked: Set(group.others.map(\.id)), onOpen: { print("open", $0) })
        .frame(height: 560)
        .padding(14)
        .background(DS.Palette.paper)
}
#endif
