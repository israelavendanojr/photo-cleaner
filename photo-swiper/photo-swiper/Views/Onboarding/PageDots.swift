import SwiftUI

/// Which onboarding page this is, as a row of small dots.
struct PageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { page in
                Capsule()
                    .fill(page == current ? DS.Palette.ink : DS.Palette.line)
                    .frame(width: page == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

#Preview {
    VStack(spacing: 20) {
        PageDots(current: 0, count: 2)
        PageDots(current: 1, count: 2)
    }
    .padding()
    .background(DS.Palette.paper)
}
