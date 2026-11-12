import SwiftUI

/// A 0...1 ring with its value as a serif number in the middle and a caption under it: the dashboard's
/// library health. Ink, never brick: it's a score, not an amount to clear. Nil shows an empty track and
/// "—", for a value still being worked out.
struct RingGauge: View {
    let value: Double?
    /// Under the ring, e.g. "Health".
    let caption: String

    @ScaledMetric(relativeTo: .title) private var diameter = DS.Ring.diameter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(DS.Palette.line, lineWidth: DS.Ring.lineWidth)
                Circle()
                    .trim(from: 0, to: clamped ?? 0)
                    .stroke(DS.Palette.ink, style: StrokeStyle(lineWidth: DS.Ring.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score.map(String.init) ?? "—")
                    .dsSerif(28, relativeTo: .title2)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: Double(score ?? 0)))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(DS.Ring.lineWidth)
            }
            .frame(width: diameter, height: diameter)
            .animation(reduceMotion ? nil : DS.Motion.calm, value: clamped)
            Text(caption)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(score.map { "\($0) out of 100" } ?? "Not worked out yet")
    }

    private var clamped: Double? { value.map { min(max($0, 0), 1) } }
    private var score: Int? { clamped.map { Int(($0 * 100).rounded()) } }
}

#Preview {
    HStack(spacing: DS.Spacing.xl) {
        RingGauge(value: 0.72, caption: "Health")
        RingGauge(value: nil, caption: "Health")
    }
    .padding(DS.Spacing.l)
    .background(DS.Palette.paper)
}

#Preview("Large text") {
    RingGauge(value: 0.4, caption: "Health")
        .padding(DS.Spacing.l)
        .background(DS.Palette.paper)
        .dynamicTypeSize(.xxLarge)
}
