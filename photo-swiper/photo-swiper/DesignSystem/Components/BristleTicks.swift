import SwiftUI

/// The tick motif: a row of upright strokes, the first `value` of them filled over a quiet track.
/// It's the app's progress bar (the feed's pile meter, the Library's share reviewed, a row's share
/// of the biggest) and, as `BristleMark`, its glyph.
///
/// The fill sweeps to a new value with the ticks appearing one at a time, from empty the first time
/// it's seen. Under Reduce Motion it shows the value at once. Give it an `accessibilityLabel` where
/// it's used; it reads its own percentage as the value.
struct BristleTicks: View {
    /// 0...1
    let value: Double
    var tint: Color = DS.Palette.ink
    /// False leaves the unfilled part empty, for a bar that only compares sizes.
    var showsTrack = true
    /// Ticks rise a little as they fill, for an amount that was just added to.
    var popsNew = false

    @ScaledMetric private var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What's drawn, on its way to `value`.
    @State private var shown = 0.0

    init(value: Double, tint: Color = DS.Palette.ink, height: CGFloat = DS.Ticks.meterHeight, showsTrack: Bool = true, popsNew: Bool = false) {
        self.value = value
        self.tint = tint
        self.showsTrack = showsTrack
        self.popsNew = popsNew
        _height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        TickRow(filled: shown, tint: tint, showsTrack: showsTrack, pops: popsNew && !reduceMotion)
            .frame(height: height)
            .onAppear { fill(to: clamped) }
            .onChange(of: clamped) { _, new in fill(to: new) }
            .accessibilityElement()
            .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }

    private func fill(to target: Double) {
        if reduceMotion {
            shown = target
        } else {
            withAnimation(DS.Motion.tickFill) { shown = target }
        }
    }
}

/// The strokes themselves. `filled` animates, and each tick fills as the sweep passes it.
private struct TickRow: View, Animatable {
    var filled: Double
    let tint: Color
    let showsTrack: Bool
    let pops: Bool

    var animatableData: Double {
        get { filled }
        set { filled = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let count = Self.count(in: size.width)
            guard count > 0 else { return }
            // At least one tick for any amount at all, so a small share doesn't read as none.
            let target = filled > 0 ? max(filled * Double(count), 0.5) : 0
            for index in 0..<count {
                let x = CGFloat(index) * DS.Ticks.pitch
                // How far the sweep is through this tick, 0...1.
                let reach = target > 0 ? min(max(target - Double(index) + 0.5, 0), 1) : 0
                if showsTrack, reach < 1 {
                    context.fill(Path(CGRect(x: x, y: 0, width: DS.Ticks.stroke, height: size.height)), with: .color(DS.Palette.outline))
                }
                guard reach > 0 else { continue }
                // A filling tick rises past its height and settles back.
                let lift = pops ? sin(reach * .pi) * size.height * DS.Ticks.popLift : 0
                var tick = context
                tick.opacity = reach
                tick.fill(Path(CGRect(x: x, y: -lift, width: DS.Ticks.stroke, height: size.height + lift)), with: .color(tint))
            }
        }
    }

    /// How many whole ticks fit.
    static func count(in width: CGFloat) -> Int {
        max(0, Int((width + DS.Ticks.pitch - DS.Ticks.stroke) / DS.Ticks.pitch))
    }
}

/// Bristle's glyph: a few ink ticks standing on a brick line. Beside the wordmark.
struct BristleMark: View {
    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = DS.Ticks.markSide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BristleTicks(value: 1, showsTrack: false)
                .frame(width: side * DS.Ticks.markTicksShare, height: side - DS.Ticks.markLine)
            Rectangle()
                .fill(DS.Palette.brick)
                .frame(height: DS.Ticks.markLine)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

#Preview("Ticks") {
    @Previewable @State var value = 0.18

    VStack(alignment: .leading, spacing: DS.Spacing.l) {
        BristleMark()
        BristleTicks(value: value, tint: DS.Palette.brick, popsNew: true)
        BristleTicks(value: 0.21, height: DS.Ticks.heroHeight)
        BristleTicks(value: 0.7, tint: DS.Palette.brick, height: DS.Ticks.rowHeight, showsTrack: false)
            .frame(width: 84)
        Button("Add") { value = min(1, value + 0.07) }
            .buttonStyle(.pill(.outline))
    }
    .padding(DS.Spacing.l)
    .paperBackground()
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: DS.Spacing.l) {
        BristleMark()
        BristleTicks(value: 0.18, tint: DS.Palette.brick)
        BristleTicks(value: 0.21, height: DS.Ticks.heroHeight)
    }
    .padding(DS.Spacing.l)
    .paperBackground()
    .preferredColorScheme(.dark)
}

#Preview("XXL") {
    BristleTicks(value: 0.4, height: DS.Ticks.heroHeight)
        .padding(DS.Spacing.l)
        .paperBackground()
        .dynamicTypeSize(.xxLarge)
}
