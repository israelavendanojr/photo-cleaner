import SwiftUI

/// This week against last week, under a big number: "+860 MB vs last week". Ink with an arrow, never brick
/// or green: more cleared isn't a warning, and less isn't a failure.
struct StatDelta: View {
    let current: Int64
    let previous: Int64
    /// "week", in "vs last week".
    var period = "week"

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(current - previous)))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(DS.Palette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var change: Int64 { current - previous }

    private var symbol: String? {
        if change > 0 { return "arrow.up.right" }
        if change < 0 { return "arrow.down.right" }
        return nil
    }

    private var text: String {
        if current == 0, previous == 0 { return "Nothing cleared this \(period)" }
        if change == 0 { return "Same as last \(period)" }
        return "\(Format.signedSize(change)) vs last \(period)"
    }

    private var spoken: String {
        if current == 0, previous == 0 { return "Nothing cleared this \(period)" }
        let now = "\(Format.size(current)) cleared this \(period)"
        if change == 0 { return "\(now), the same as last \(period)" }
        return "\(now), \(Format.size(abs(change))) \(change > 0 ? "more" : "less") than last \(period)"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DS.Spacing.s) {
        StatDelta(current: 1_200_000_000, previous: 340_000_000)
        StatDelta(current: 100_000_000, previous: 900_000_000)
        StatDelta(current: 50_000_000, previous: 50_000_000)
        StatDelta(current: 0, previous: 0)
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}
