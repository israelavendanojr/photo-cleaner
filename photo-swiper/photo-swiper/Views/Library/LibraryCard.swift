import SwiftUI

/// The library in one card: how much is reviewed, what its space is made of, and one chip per thing worth
/// a look. The selected chip lights up its part of the bar and shows its count, size, biggest few items,
/// and a way into a feed of just those. One choice at a time, so the card stays calm.
struct LibraryCard: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The dashboard's numbers, or a stand-in while they load.
    let snapshot: DashboardSnapshot
    var isLoading = false
    /// "Review these" is the screen's main action, so it's ink; otherwise outlined, under the hero's own.
    var isPrimary = true

    /// The chip the user picked; nil until they pick one, so the default can follow the numbers.
    @State private var picked: FocusTarget?

    @ScaledMetric(relativeTo: .body) private var barHeight = DS.Chart.stackedBarHeight
    @ScaledMetric(relativeTo: .body) private var swatchSize = DS.Chart.swatchSize
    @ScaledMetric(relativeTo: .body) private var thumbSize = DS.LibraryCard.thumbSize

    private var chips: [DashboardSnapshot.Chip] { snapshot.chips ?? [] }
    private var slices: [DashboardSnapshot.Slice] { snapshot.composition ?? [] }

    /// The picked chip while it's still there, else the one with the most to recover.
    private var selected: DashboardSnapshot.Chip? {
        chips.first { $0.focus == picked } ?? chips.first { $0.focus == snapshot.defaultChip } ?? chips.first
    }

    var body: some View {
        DashboardCard {
            reviewed
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                if !slices.isEmpty {
                    composition
                        .redacted(reason: isLoading ? .placeholder : [])
                }
                if chips.isEmpty {
                    Text(snapshot.scanPercent.map { "Still looking through your library (\(Format.percent(Double($0) / 100)))." }
                        ?? "Nothing obvious left to look at.")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    chipRow
                    if let selected {
                        detail(selected)
                            .redacted(reason: isLoading ? .placeholder : [])
                    }
                }
            }
        }
        .disabled(isLoading)
    }

    // MARK: Reviewed

    private var reviewed: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(Format.percent(vm.libraryReviewedFraction))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: vm.libraryReviewedFraction))
                Text("reviewed")
                    .font(.callout)
            }
            .foregroundStyle(DS.Palette.ink)
            ProgressLine(value: vm.libraryReviewedFraction, height: 4)
            Text("\(Format.count(vm.libraryReviewedCount)) of \(Format.count(vm.stats.totalItems)) photos and videos")
                .font(.footnote)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Composition

    /// The slice the selected chip is part of, if any. The bar then shows only it in ink.
    private var highlighted: LibraryProfile.Kind? { selected?.focus.kind }

    private func shade(_ slice: DashboardSnapshot.Slice, at offset: Int) -> Color {
        if let highlighted { return slice.kind == highlighted ? DS.Palette.ink : DS.Palette.line }
        let opacities = DS.Chart.categoryOpacities
        return DS.Palette.ink.opacity(opacities[min(offset, opacities.count - 1)])
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            bar
            legend
        }
        .animation(reduceMotion ? nil : DS.Motion.calm, value: highlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("What your library is made of")
        .accessibilityValue(slices.map { "\($0.kind.title), \(Format.size($0.bytes))" }.joined(separator: "; "))
    }

    private var bar: some View {
        GeometryReader { proxy in
            let gaps = DS.Chart.segmentGap * Double(max(slices.count - 1, 0))
            let width = max(0, proxy.size.width - gaps)
            HStack(spacing: DS.Chart.segmentGap) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { offset, slice in
                    Rectangle()
                        .fill(shade(slice, at: offset))
                        .frame(width: width * slice.share)
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(Capsule())
    }

    /// A swatch and a name for each slice, so the shades never have to say what's what on their own.
    private var legend: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.s, alignment: .leading),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.xs) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { offset, slice in
                HStack(spacing: DS.Spacing.xs) {
                    RoundedRectangle(cornerRadius: DS.Chart.heatCellRadius, style: .continuous)
                        .fill(shade(slice, at: offset))
                        .frame(width: swatchSize, height: swatchSize)
                    Text("\(slice.kind.title) \(Format.size(slice.bytes))")
                        .font(.footnote.weight(slice.kind == highlighted ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Chips

    private var chipRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(chips) { chip in
                        let isSelected = chip.focus == selected?.focus
                        Button {
                            withAnimation(reduceMotion ? nil : DS.Motion.calm) { picked = chip.focus }
                        } label: {
                            Chip(text: chip.focus.chipTitle, style: isSelected ? .selected : .option)
                                .frame(minHeight: DS.Tap.minimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .id(chip.focus)
                        .accessibilityLabel(chip.focus.chipTitle)
                        .accessibilityValue("\(chip.focus.count(chip.count)), \(Format.size(chip.bytes))")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("library.chip.\(chip.focus.identifier)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            // The default may be any chip; bring it into view rather than leave it off the edge.
            .onAppear { if let focus = selected?.focus { proxy.scrollTo(focus, anchor: .center) } }
            .onChange(of: snapshot.defaultChip) {
                guard picked == nil, let focus = selected?.focus else { return }
                withAnimation(reduceMotion ? nil : DS.Motion.calm) { proxy.scrollTo(focus, anchor: .center) }
            }
        }
    }

    private func detail(_ chip: DashboardSnapshot.Chip) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        countText(chip)
                        Spacer(minLength: DS.Spacing.xs)
                        sizeText(chip)
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        countText(chip)
                        sizeText(chip)
                    }
                }
                Text(chip.focus.detail)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !chip.thumbnails.isEmpty {
                strip(chip.thumbnails)
            }
            Button("Review these") {
                Haptics.advance()
                vm.focusFeed(on: chip.focus)
            }
            .buttonStyle(.pill(isPrimary ? .ink : .outline))
            .accessibilityHint("Shows only \(chip.focus.phrase) in the feed")
            .accessibilityIdentifier("library.review")
        }
        .id(chip.focus)
        .transition(.opacity)
    }

    private func countText(_ chip: DashboardSnapshot.Chip) -> some View {
        Text(chip.focus.count(chip.count))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.ink)
            .contentTransition(.numericText(value: Double(chip.count)))
    }

    /// Brick for what clearing would free (the cleanup categories), ink for the library's own kinds and
    /// what's saved for later, which are sizes, not amounts to clear.
    private func sizeText(_ chip: DashboardSnapshot.Chip) -> some View {
        let isToClear = if case .category = chip.focus { true } else { false }
        return Text(Format.size(chip.bytes))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(isToClear ? DS.Palette.brick : DS.Palette.ink)
            .contentTransition(.numericText(value: Double(chip.bytes)))
    }

    /// The chip's biggest items, in equal squares that share the width, at most `thumbSize` each.
    private func strip(_ thumbnails: [ImageReference]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(maximum: thumbSize), spacing: DS.Spacing.xxs), count: LibraryScan.sampleCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.xxs) {
            ForEach(Array(thumbnails.prefix(LibraryScan.sampleCount).enumerated()), id: \.offset) { _, reference in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ItemImage(reference) }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}

extension LibraryProfile.Kind {
    /// "Live Photos", in the composition bar's key.
    var title: String {
        switch self {
        case .video: "Videos"
        case .livePhoto: "Live Photos"
        case .screenshot: "Screenshots"
        case .photo: "Other photos"
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        LibraryCard(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
}

#Preview("Large text") {
    ScrollView {
        LibraryCard(snapshot: .preview)
            .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .environment(FeedViewModel.mock(startingAt: .batch))
    .dynamicTypeSize(.accessibility5)
}

#Preview("Still analyzing, nothing found") {
    var snapshot = DashboardSnapshot.preview
    snapshot.chips = []
    snapshot.scanPercent = 12
    return LibraryCard(snapshot: snapshot)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}

#Preview("Loading") {
    LibraryCard(snapshot: .placeholder(), isLoading: true)
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}
#endif
