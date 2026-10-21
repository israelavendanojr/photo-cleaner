import SwiftUI

/// The main feed's deck, wired to the session: swipes decide cards, and a batch card opens
/// its one-by-one review on top.
struct CardStackView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var request: SwipeDirection?
    /// The batch being gone through one by one, and its outcome once finished.
    @State private var reviewingBatch: ItemBatch?
    @State private var batchOutcome: [LibraryItem.ID: Decision]?
    @AppStorage(DefaultsKey.hasSeenSwipeHint) private var hasSeenSwipeHint = false

    var body: some View {
        SwipeDeck(
            cards: vm.cards,
            index: vm.index,
            returning: vm.returningCard,
            label: vm.swipeLabel,
            onDecide: decide,
            request: $request,
            onOpenBatch: { reviewingBatch = $0 },
            showsHint: !hasSeenSwipeHint
        )
        .fullScreenCover(item: $reviewingBatch, onDismiss: flyOutReviewedBatch) { batch in
            BatchReviewView(batch: batch, draft: vm.draft(for: batch)) { outcome in
                batchOutcome = outcome
                reviewingBatch = nil
            }
        }
    }

    /// Once the review cover is gone, the batch card leaves like a normal swipe.
    private func flyOutReviewedBatch() {
        guard let outcome = batchOutcome else { return }
        request = outcome.values.contains(.delete) ? .left : .right
    }

    private func decide(_ direction: SwipeDirection, card: FeedCard) {
        hasSeenSwipeHint = true
        if let outcome = batchOutcome {
            batchOutcome = nil
            vm.decideIndividually(outcome)
            return
        }
        if direction == .left, vm.bytesToClear(for: card) > 0 {
            Haptics.delete()
        }
        vm.decide(direction)
    }
}

#Preview {
    CardStackView()
        .environment(FeedViewModel.mock())
        .background(DS.Palette.paper)
}
