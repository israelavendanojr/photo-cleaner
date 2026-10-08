import SwiftUI

/// The top card, the card peeking behind it, and the action buttons that drive them.
struct CardStackView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var request: SwipeDirection?
    /// How far the top card is toward committing, 0...1.
    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // One ForEach keyed by card ID so a card keeps its identity as it moves
                // between "behind" and "on top" (promotion after a swipe, demotion on undo).
                ForEach(visibleCards) { card in
                    let isTop = card.id == vm.currentCard?.id
                    SwipeableCard(
                        isEnabled: isTop,
                        entrance: entrance(for: card),
                        label: { vm.swipeLabel($0, for: card) },
                        request: isTop ? $request : .constant(nil),
                        progress: isTop ? $progress : .constant(0),
                        onSwipe: { commit($0, card: card) }
                    ) {
                        CardContentView(card: card)
                    }
                    .scaleEffect(isTop ? 1 : 0.95 + 0.05 * progress)
                    .offset(y: isTop ? 0 : 12 * (1 - progress))
                    .allowsHitTesting(isTop)
                    .zIndex(isTop ? 1 : 0)
                    .transition(isTop ? .identity : .opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, DS.Spacing.cardInset)
            .frame(maxHeight: .infinity)

            ActionBar { request = $0 }
                .disabled(vm.currentCard == nil)
        }
    }

    private var visibleCards: [FeedCard] {
        [vm.currentCard, vm.nextCard].compactMap { $0 }
    }

    private func entrance(for card: FeedCard) -> SwipeDirection? {
        guard let returning = vm.returningCard, returning.cardID == card.id else { return nil }
        return returning.direction
    }

    private func commit(_ direction: SwipeDirection, card: FeedCard) {
        if direction == .left, vm.bytesToClear(for: card) > 0 {
            Haptics.delete()
        }
        withAnimation(DS.Motion.calm) {
            progress = 0
            vm.decide(direction)
        }
    }
}

#Preview {
    CardStackView()
        .environment(FeedViewModel.mock())
        .background(DS.Palette.paper)
}
