import SwiftUI

/// Three photo-like cards fanned out, drawn with gradients. Decorative only.
struct StackedPhotosIllustration: View {
    /// Drawn at the mockup's 250×240 and scaled to fit the rest of the screen above the fold.
    var scale: CGFloat = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    /// Fast out with a long soft tail, like the cards settling onto a table.
    private static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 1.2)

    var body: some View {
        let settled = isSettled || reduceMotion
        ZStack(alignment: .topLeading) {
            photo(width: 150, height: 190, stops: [(0xD6E2D4, 0), (0x7F9A76, 1)])
                .rotationEffect(.degrees(settled ? 8 : 0))
                .offset(x: 100 + (settled ? 0 : -20), y: 40)
            photo(width: 160, height: 210, stops: [(0xBCD6E0, 0), (0xECE3D4, 0.55), (0xD8C094, 0.56), (0xC6A878, 1)])
                .offset(x: 74, y: 24 + (settled ? 0 : 10))
            photo(width: 130, height: 170, stops: [(0xF2C39A, 0), (0xE49A7A, 0.5), (0x7F5A72, 1)])
                .offset(x: settled ? 0 : 20)
        }
        .frame(width: 250, height: 240, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 250 * scale, height: 240 * scale, alignment: .topLeading)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Self.settle) { isSettled = true }
        }
    }

    /// Illustration fills, not palette colors.
    private func photo(width: CGFloat, height: CGFloat, stops: [(UInt32, Double)]) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous)
            .fill(LinearGradient(
                stops: stops.map { .init(color: Color(hex: $0.0), location: $0.1) },
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: width, height: height)
            .cardShadow()
    }
}

#Preview {
    StackedPhotosIllustration()
        .padding(40)
        .background(DS.Palette.paper)
}
