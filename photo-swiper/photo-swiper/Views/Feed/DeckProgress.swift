import SwiftUI

/// The center of a deck's top bar: an optional title, "12 of 20", and a progress line.
struct DeckProgress<Footer: View>: View {
    var title: String?
    let position: Int
    let total: Int
    /// Fraction done, 0...1.
    let value: Double
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 6) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
            }
            Text("\(position) of \(total)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.secondary)
                .contentTransition(.numericText(value: Double(position)))
            ProgressLine(value: value)
                .frame(width: 96)
            footer
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

extension DeckProgress where Footer == EmptyView {
    init(title: String? = nil, position: Int, total: Int, value: Double) {
        self.init(title: title, position: position, total: total, value: value) { EmptyView() }
    }
}

#Preview {
    DeckProgress(title: "Screenshots", position: 3, total: 14, value: 2 / 14)
        .padding()
        .background(DS.Palette.paper)
}
