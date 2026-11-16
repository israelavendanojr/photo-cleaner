import SwiftUI

/// The brick serif running total with its label beside it on the baseline ("184 MB of 1 GB"), and a
/// small "+3.4 MB" chip that pops above it. Where the two don't fit side by side, the label drops
/// under the number.
struct ToClearCounter: View {
    let bytes: Int64
    var label: String = "to clear"
    /// What VoiceOver reads after the size, when it should differ from `label`, e.g. "to clear, 12 of 50 photos".
    var accessibilityText: String?
    /// Tints the label, e.g. when a free user's pile is full.
    var isLabelEmphasized = false
    /// Bytes just added. Shown as a chip while non-nil.
    var addedBytes: Int64?
    /// Changes whenever a new chip should pop, even for equal amounts.
    var addedID: AnyHashable?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                total.fixedSize()
                caption.fixedSize()
            }
            VStack(alignment: .trailing, spacing: 0) {
                total.minimumScaleFactor(0.6)
                caption
            }
        }
        .overlay(alignment: .topTrailing) {
            if let addedBytes, addedBytes > 0 {
                Text("+\(Format.size(addedBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.brick)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(DS.Palette.brickTint, in: Capsule())
                    .fixedSize()
                    .offset(y: -26)
                    .id(addedID)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    ))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.size(bytes)) \(accessibilityText ?? label)")
    }

    private var total: some View {
        Text(Format.size(bytes))
            .dsSerif(34, relativeTo: .title)
            .tracking(-0.5)
            .foregroundStyle(DS.Palette.brick)
            .contentTransition(.numericText(value: Double(bytes)))
            .lineLimit(1)
    }

    private var caption: some View {
        Text(label)
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(isLabelEmphasized ? DS.Palette.brick : DS.Palette.secondary)
            .lineLimit(1)
    }
}

#Preview {
    @Previewable @State var bytes: Int64 = 184_000_000
    @Previewable @State var added: Int64?

    VStack(spacing: 40) {
        ToClearCounter(bytes: bytes, addedBytes: added, addedID: bytes)
        Button("Add 3.4 MB") {
            withAnimation(DS.Motion.calm) {
                bytes += 3_400_000
                added = 3_400_000
            }
        }
    }
    .padding(DS.Spacing.xxl)
    .paperBackground()
}
