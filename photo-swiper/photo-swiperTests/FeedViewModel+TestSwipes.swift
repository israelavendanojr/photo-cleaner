@testable import photo_swiper

/// Swipes whatever card is on top, as the deck does when nothing moves underneath it.
/// Tests about other things use these; `CardIdentityTests` names the card explicitly.
@MainActor
extension FeedViewModel {
    private var topCardID: FeedCard.ID { currentCard?.id ?? "" }

    func decideCurrent(_ direction: SwipeDirection) {
        decide(direction, cardID: topCardID)
    }

    func decideCurrentIndividually(_ outcome: [LibraryItem.ID: Decision]) {
        decideIndividually(outcome, cardID: topCardID)
    }

    func canDecideCurrent(_ direction: SwipeDirection) -> Bool {
        canDecide(direction, cardID: topCardID)
    }

    func canDecideCurrentIndividually(_ outcome: [LibraryItem.ID: Decision]) -> Bool {
        canDecideIndividually(outcome, cardID: topCardID)
    }

    func refuseCurrent(_ direction: SwipeDirection) {
        refuse(direction, cardID: topCardID)
    }
}
