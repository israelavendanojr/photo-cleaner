import SwiftUI

/// The top card, the card peeking behind it, and the action buttons that drive them.
struct CardStackView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var request: SwipeDirection?
    /// How far the top card is toward committing, 0...1.
    @State private var progress = 0.0
    @State private var cardSize = CGSize.zero
    /// The batch being gone through one by one, and its outcome once finished.
    @State private var reviewingBatch: ItemBatch?
    @State private var batchOutcome: [LibraryItem.ID: Decision]?
    @Environment(\.displayScale) private var displayScale

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
                        CardContentView(card: card) { reviewingBatch = $0 }
                    }
                    .scaleEffect(isTop ? 1 : 0.95 + 0.05 * progress)
                    .offset(y: isTop ? 0 : 12 * (1 - progress))
                    .allowsHitTesting(isTop)
                    .zIndex(isTop ? 1 : 0)
                    .transition(isTop ? .identity : .opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
            .padding(.horizontal, DS.Spacing.cardInset)
            .frame(maxHeight: .infinity)

            ActionBar { request = $0 }
                .disabled(vm.currentCard == nil)
        }
        .fullScreenCover(item: $reviewingBatch, onDismiss: flyOutReviewedBatch) { batch in
            BatchReviewView(batch: batch) { outcome in
                batchOutcome = outcome
                reviewingBatch = nil
            }
        }
        .task(id: preheatWindow) {
            ThumbnailPipeline.shared.preheat(preheatWindow)
        }
    }

    /// Library images for the cards on screen and the next few, at the sizes they'll be shown,
    /// so swiping never lands on a blank card. Everything outside the window is released.
    private var preheatWindow: [String: CGSize] {
        guard cardSize != .zero else { return [:] }
        let cardPixels = ThumbnailPipeline.pixelSize(for: cardSize, scale: displayScale)
        let tilePixels = ThumbnailPipeline.pixelSize(for: ScreenshotBatchCardView.tileSize, scale: displayScale)
        var window: [String: CGSize] = [:]
        for card in vm.cards.dropFirst(vm.index).prefix(6) {
            switch card {
            case .photo(let item), .video(let item):
                if let id = item.image.localIdentifier { window[id] = cardPixels }
            case .batch(let batch):
                for item in batch.items.prefix(ScreenshotBatchCardView.fannedCount) {
                    if let id = item.image.localIdentifier { window[id] = tilePixels }
                }
            case .similar:
                break
            }
        }
        return window
    }

    private var visibleCards: [FeedCard] {
        [vm.currentCard, vm.nextCard].compactMap { $0 }
    }

    private func entrance(for card: FeedCard) -> SwipeDirection? {
        guard let returning = vm.returningCard, returning.cardID == card.id else { return nil }
        return returning.direction
    }

    /// Once the review cover is gone, the batch card leaves like a normal swipe.
    private func flyOutReviewedBatch() {
        guard let outcome = batchOutcome else { return }
        request = outcome.values.contains(.delete) ? .left : .right
    }

    private func commit(_ direction: SwipeDirection, card: FeedCard) {
        if let outcome = batchOutcome {
            batchOutcome = nil
            withAnimation(DS.Motion.calm) {
                progress = 0
                vm.decideIndividually(outcome)
            }
            return
        }
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
