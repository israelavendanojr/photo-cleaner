import SwiftUI

/// The main feed's deck, wired to the view model: swipes decide cards, and a batch or
/// similar-shots card opens its one-by-one review on top.
struct CardStackView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var request: SwipeDirection?
    /// The card being gone through one by one, and its outcome once finished.
    @State private var reviewing: ReviewSet?
    @State private var finishedReview: FinishedReview?
    @AppStorage(DefaultsKey.hasSeenSwipeHint) private var hasSeenSwipeHint = false
    @Environment(\.dealsInFirstDeck) private var dealsIn

    var body: some View {
        SwipeDeck(
            cards: vm.cards,
            index: vm.index,
            returning: vm.returningCard,
            label: vm.swipeLabel,
            onDecide: decide,
            request: $request,
            onOpenReview: { reviewing = $0 },
            showsHint: !hasSeenSwipeHint,
            dealsIn: dealsIn,
            canSwipe: canDecide,
            onRefused: refused,
            waitingText: vm.isFindingMore ? "Finding more…" : nil
        )
        #if DEBUG
        .overlay(alignment: .top) { CurrentCardMarker() }
        #endif
        .fullScreenCover(item: $reviewing, onDismiss: flyOutReviewedCard) { set in
            ItemReviewView(set: set, draft: vm.draft(for: set.id)) { outcome in
                finishedReview = FinishedReview(cardID: set.id, outcome: outcome)
                reviewing = nil
            }
        }
    }

    /// Once the review cover is gone, the card leaves like a normal swipe.
    private func flyOutReviewedCard() {
        guard let review = finishedReview else { return }
        request = review.outcome.values.contains(.delete) ? .left : .right
    }

    /// A finished one-by-one review is judged by its own outcome, which isn't a draft yet.
    private func canDecide(_ direction: SwipeDirection, card: FeedCard) -> Bool {
        if let review = finishedReview {
            return vm.canDecideIndividually(review.outcome, cardID: review.cardID)
        }
        return vm.canDecide(direction, cardID: card.id)
    }

    /// Out of swipes or a full pile. A finished one-by-one review waits as a draft for the next swipe.
    private func refused(_ direction: SwipeDirection, card: FeedCard) {
        if let review = finishedReview {
            vm.saveDraft(review.outcome, for: review.cardID)
        }
        finishedReview = nil
        vm.refuse(direction, cardID: card.id)
    }

    /// Decisions always name their card, so one that moved meanwhile is never decided by mistake.
    private func decide(_ direction: SwipeDirection, card: FeedCard) {
        hasSeenSwipeHint = true
        if let review = finishedReview {
            finishedReview = nil
            vm.decideIndividually(review.outcome, cardID: review.cardID)
            return
        }
        if direction == .left, vm.bytesToClear(for: card) > 0 {
            Haptics.delete()
        }
        vm.decide(direction, cardID: card.id)
    }
}

/// A one-by-one review's outcome, kept with the card it was for until the card flies out.
private struct FinishedReview {
    let cardID: FeedCard.ID
    let outcome: [LibraryItem.ID: Decision]
}

#if DEBUG
/// Names the top card for UI tests, which can't see a position now that the deck has no end.
/// Only with the mock library.
private struct CurrentCardMarker: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        if LibraryServices.usesMock {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(vm.currentCard?.id ?? "none")
                .accessibilityIdentifier("feed.currentCard")
        }
    }
}

#Preview {
    CardStackView()
        .environment(FeedViewModel.mock())
        .background(DS.Palette.paper)
}
#endif
