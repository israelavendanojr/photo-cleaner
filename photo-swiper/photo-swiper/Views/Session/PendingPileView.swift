import SwiftUI

/// Everything waiting to be cleared. Tap an item to look at it full screen and keep it instead.
///
/// Opens as a sheet from the feed's "to clear" counter, or pushed from the overview's Pending row.
struct PendingPileView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    /// True when presented on its own as a sheet; pushed, the navigation bar's back button closes it.
    var showsDone = false

    @State private var previewing: LibraryItem?

    private var count: Int { vm.pendingItems.count }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if vm.pendingItems.isEmpty {
                    Text("Nothing marked to clear.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(vm.pendingItems) { item in
                            Button { previewing = item } label: { PendingTile(item: item) }
                                .buttonStyle(PressScaleStyle())
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.top, DS.Spacing.l)
                    Text("Nothing is deleted until you confirm at the end of a session. Tap one to keep it instead.")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.l)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .fullScreenCover(item: $previewing) { item in
            if item.isVideo {
                VideoPreviewView(item: item) { keep(item) }
            } else {
                PhotoPreviewView(item: item) { keep(item) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pending")
                    .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                Spacer()
                if showsDone {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                }
            }
            Text(Format.size(vm.pendingBytes))
                .dsSerif(48, relativeTo: .largeTitle)
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(vm.pendingBytes)))
                .padding(.top, DS.Spacing.s)
            Text("to clear from \(count) \(count == 1 ? "photo" : "photos")")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
        }
        .padding(.top, showsDone ? DS.Spacing.xl : DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func keep(_ item: LibraryItem) {
        withAnimation(DS.Motion.calm) { vm.keepInstead(item) }
    }
}

private struct PendingTile: View {
    let item: LibraryItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ItemImage(item.image) }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if let duration = item.duration {
                        Image(systemName: "play.fill")
                        Text(Format.duration(duration))
                    } else {
                        Text(Format.size(item.bytes))
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Opens full screen")
            .accessibilityIdentifier("pendingTile")
    }

    private var accessibilityText: String {
        [item.isVideo ? "Video" : "Photo", Format.size(item.bytes), Format.day(item.date)].joined(separator: ", ")
    }
}

#Preview("Sheet") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock(startingAt: .end))
}

#Preview("Empty") {
    PendingPileView(showsDone: true)
        .environment(FeedViewModel.mock())
}
