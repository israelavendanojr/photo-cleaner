import SwiftUI

/// A ruled row that tallies one thing: its name and count, a short run of ticks for its share, its size,
/// and a chevron when it leads somewhere. The Library's lists and its bin are made of these. It draws no
/// rule of its own; put a `Rule` above each and one after the last.
///
/// At accessibility sizes the count and size go under the name and the ticks under those, so nothing
/// truncates. Give it its VoiceOver label and value where it's used: the ticks are hidden.
struct TallyRow: View {
    let title: String
    let count: Int
    /// The ticks' fill, 0...1. Nil draws none.
    var share: Double?
    /// Draws the empty ticks too, for a share of a limit rather than of the biggest row.
    var showsTrack = false
    let bytes: Int64
    /// Brick when the size is an amount to clear, ink otherwise.
    var tint: Color = DS.Palette.ink
    var showsChevron = true
    /// A line under the row, e.g. that the bin is full.
    var note: String?

    @ScaledMetric(relativeTo: .subheadline) private var ticksWidth = DS.Tally.ticksWidth
    @ScaledMetric(relativeTo: .subheadline) private var sizeWidth = DS.Tally.sizeWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                inline
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: DS.Tally.minHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var inline: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                // One line beside the columns; a long name gives a little rather than wrapping.
                titleText
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                countText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ticks
                .frame(width: ticksWidth, alignment: .leading)
            sizeText
                .frame(minWidth: sizeWidth, alignment: .trailing)
            chevron
        }
    }

    private var stacked: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                titleText
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    countText
                    sizeText
                }
                ticks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chevron
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(DS.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var countText: some View {
        Text(Format.count(count))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(DS.Palette.secondary)
            .contentTransition(.numericText(value: Double(count)))
    }

    private var sizeText: some View {
        Text(Format.size(bytes))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText(value: Double(bytes)))
            .lineLimit(1)
    }

    @ViewBuilder private var ticks: some View {
        if let share {
            BristleTicks(value: share, tint: tint, height: DS.Ticks.rowHeight, showsTrack: showsTrack)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    /// Kept in the layout when hidden, so the sizes line up down the page.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(DS.Palette.secondary)
            .opacity(showsChevron ? 1 : 0)
            .accessibilityHidden(true)
    }
}

#Preview("Rows") {
    VStack(spacing: 0) {
        Rule()
        TallyRow(title: "Bin", count: 12, share: 0.18, showsTrack: true, bytes: 184_000_000, tint: DS.Palette.brick)
        Rule()
        TallyRow(title: "Duplicates", count: 214, share: 1, bytes: 1_870_000_000)
        Rule()
        TallyRow(title: "Accidental shots", count: 140, share: 0.22, bytes: 410_000_000)
        Rule()
        TallyRow(title: "Videos", count: 1_120, share: 0.6, bytes: 18_700_000_000)
        Rule()
    }
    .padding(DS.Spacing.l)
    .paperBackground()
}

#Preview("Dark") {
    VStack(spacing: 0) {
        Rule()
        TallyRow(title: "Duplicates", count: 214, share: 1, bytes: 1_870_000_000)
        Rule()
        TallyRow(title: "Videos", count: 1_120, share: 0.6, bytes: 18_700_000_000)
        Rule()
    }
    .padding(DS.Spacing.l)
    .paperBackground()
    .preferredColorScheme(.dark)
}

#Preview("Large text") {
    VStack(spacing: 0) {
        Rule()
        TallyRow(title: "Bin", count: 140, share: 1, showsTrack: true, bytes: 1_000_000_000, tint: DS.Palette.brick,
                 note: "Full at 1 GB. Delete these to keep clearing.")
        Rule()
    }
    .padding(DS.Spacing.l)
    .paperBackground()
    .dynamicTypeSize(.accessibility2)
}
