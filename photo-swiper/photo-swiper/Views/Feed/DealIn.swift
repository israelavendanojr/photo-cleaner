import SwiftUI

extension EnvironmentValues {
    /// The feed is appearing straight from onboarding, so its deck deals in.
    @Entry var dealsInFirstDeck = false
}

/// Drops a card into place from above, for the deck after onboarding. Fades only with Reduce Motion.
struct DealIn: ViewModifier {
    let isDealt: Bool
    /// Back card first, then the top card, then the buttons.
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let step = 0.09

    func body(content: Content) -> some View {
        let moves = !isDealt && !reduceMotion
        content
            .opacity(isDealt ? 1 : 0)
            .scaleEffect(moves ? 0.92 : 1)
            .rotationEffect(.degrees(moves ? (order.isMultiple(of: 2) ? 2 : -3) : 0))
            .offset(y: moves ? -90 : 0)
            .animation(DS.Motion.calm.delay(Double(order) * Self.step), value: isDealt)
    }
}
