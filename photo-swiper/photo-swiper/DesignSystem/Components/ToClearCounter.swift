import SwiftUI

/// The red serif running total, with a small "+3.4 MB" chip that pops above it.
struct ToClearCounter: View {
    let bytes: Int64
    var label: String = "to clear"
    /// Bytes just added. Shown as a chip while non-nil.
    var addedBytes: Int64?
    /// Changes whenever a new chip should pop, even for equal amounts.
    var addedID: AnyHashable?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Format.size(bytes))
                .dsSerif(28, relativeTo: .title2)
                .foregroundStyle(DS.Palette.brick)
                .contentTransition(.numericText(value: Double(bytes)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Palette.secondary)
        }
        .overlay(alignment: .topTrailing) {
            if let addedBytes, addedBytes > 0 {
                Text("+\(Format.size(addedBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.brick)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
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
        .accessibilityLabel("\(Format.size(bytes)) \(label)")
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
    .padding(60)
    .background(DS.Palette.paper)
}
