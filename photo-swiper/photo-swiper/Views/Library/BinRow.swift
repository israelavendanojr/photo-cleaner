import SwiftUI

/// The pile on the dashboard, as one ruled row: "Bin", how many are in it, and their size, in brick since
/// it's what will be deleted. With a free limit, ticks show how close the pile is to full, and once it is
/// the row says so. Empty, it reads the same with zeros and no chevron: there's nothing to open. Wrap it in
/// the link to the pile only when there's something in it.
struct BinRow: View {
    let count: Int
    /// The pile's real size, as shown.
    let bytes: Int64
    /// The free limit, with what counts toward it. Nil when unlocked: there's no limit to show.
    var limit: (counted: Int64, bytes: Int64)?

    private var fill: Double? {
        limit.map { min(1, Double($0.counted) / Double(max($0.bytes, 1))) }
    }

    private var isFull: Bool { limit.map { $0.counted >= $0.bytes } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            TallyRow(
                title: "Bin", count: count, share: fill, showsTrack: true, bytes: bytes, tint: DS.Palette.brick,
                showsChevron: count > 0,
                note: limit.flatMap { isFull ? "Full at \(Format.limit($0.bytes)). Delete these to keep clearing." : nil }
            )
            Rule()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Bin", "\(Format.count(count)) \(count == 1 ? "photo" : "photos") to clear", Format.size(bytes)]
        if let limit, let fill { parts.append(isFull ? "full" : "\(Format.percent(fill)) of \(Format.limit(limit.bytes))") }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Free") {
    VStack(spacing: DS.Spacing.l) {
        BinRow(count: 0, bytes: 0, limit: (0, 2_000_000_000))
        BinRow(count: 41, bytes: 900_000_000, limit: (900_000_000, 2_000_000_000))
        BinRow(count: 104, bytes: 2_010_000_000, limit: (2_010_000_000, 2_000_000_000))
    }
    .padding(DS.Spacing.l)
    .paperBackground()
}

#Preview("Unlocked, dark") {
    BinRow(count: 41, bytes: 900_000_000)
        .padding(DS.Spacing.l)
        .paperBackground()
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    ScrollView {
        BinRow(count: 104, bytes: 2_010_000_000, limit: (2_010_000_000, 2_000_000_000))
            .padding(DS.Spacing.l)
    }
    .paperBackground()
    .dynamicTypeSize(.accessibility2)
}
#endif
