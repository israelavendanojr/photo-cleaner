import SwiftUI

/// The pile on the dashboard: a trash circle, like the feed's Delete, with how much is in it. With a free
/// limit, a brick line shows how close it is to full. Brick throughout: it's what will be deleted. Empty,
/// it looks the same with zeros and an empty line, so the card doesn't change shape as the pile fills. Wrap
/// it in the link to the pile; it draws no chevron of its own when empty, since there's nothing to open.
struct BinCard: View {
    let count: Int
    /// The pile's real size, as shown.
    let bytes: Int64
    /// The free limit, with what counts toward it. Nil when unlocked: there's no limit to show.
    var limit: (counted: Int64, bytes: Int64)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var diameter = DS.Bin.iconDiameter

    private var isEmpty: Bool { count == 0 }
    private var fill: Double {
        guard let limit else { return 0 }
        return min(1, Double(limit.counted) / Double(max(limit.bytes, 1)))
    }
    private var isFull: Bool { limit.map { $0.counted >= $0.bytes } ?? false }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Spacing.m))
        layout {
            Image(systemName: "trash")
                .font(.title3.weight(.medium))
                .foregroundStyle(DS.Palette.brick)
                .frame(width: diameter, height: diameter)
                .background(DS.Palette.brickTint, in: Circle())
                .accessibilityHidden(true)
            text
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isEmpty, !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
                .fill(DS.Palette.card)
                .softShadow()
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("Bin")
                .font(.headline)
                .foregroundStyle(DS.Palette.ink)
            Text("\(Format.count(count)) to clear · \(Format.size(bytes))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(bytes)))
                .fixedSize(horizontal: false, vertical: true)
            if let limit {
                ProgressLine(value: fill, tint: DS.Palette.brick)
                    .animation(reduceMotion ? nil : DS.Motion.calm, value: fill)
                    .padding(.top, DS.Spacing.xxs)
                Text(isFull ? "Full at \(Format.limit(limit.bytes)). Delete these to keep clearing."
                    : "\(Format.size(limit.counted)) of \(Format.limit(limit.bytes))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["Bin", "\(Format.count(count)) \(count == 1 ? "photo" : "photos") to clear", Format.size(bytes)]
        if let limit { parts.append(isFull ? "full" : "\(Format.percent(fill)) of \(Format.limit(limit.bytes))") }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Free") {
    VStack(spacing: DS.Spacing.m) {
        BinCard(count: 0, bytes: 0, limit: (0, 2_000_000_000))
        BinCard(count: 41, bytes: 900_000_000, limit: (900_000_000, 2_000_000_000))
        BinCard(count: 96, bytes: 1_850_000_000, limit: (1_850_000_000, 2_000_000_000))
        BinCard(count: 104, bytes: 2_010_000_000, limit: (2_010_000_000, 2_000_000_000))
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}

#Preview("Unlocked") {
    VStack(spacing: DS.Spacing.m) {
        BinCard(count: 0, bytes: 0)
        BinCard(count: 1, bytes: 3_400_000)
        BinCard(count: 214, bytes: 4_300_000_000)
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    ScrollView {
        VStack(spacing: DS.Spacing.m) {
            BinCard(count: 96, bytes: 1_850_000_000, limit: (1_850_000_000, 2_000_000_000))
            BinCard(count: 214, bytes: 4_300_000_000)
        }
        .padding(DS.Spacing.l)
    }
    .background(DS.Palette.paper)
    .dynamicTypeSize(.accessibility5)
}
#endif
