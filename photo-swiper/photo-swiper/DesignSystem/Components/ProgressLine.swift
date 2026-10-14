import SwiftUI

/// Thin rounded progress track.
struct ProgressLine: View {
    /// 0...1
    let value: Double
    var tint: Color = DS.Palette.ink
    var height: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(DS.Palette.line)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressLine(value: 0.24).frame(width: 96)
        ProgressLine(value: 0.21, tint: DS.Palette.brick, height: 4)
    }
    .padding()
    .background(DS.Palette.paper)
}
