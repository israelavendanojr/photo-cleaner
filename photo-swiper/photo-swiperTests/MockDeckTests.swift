import Testing
@testable import photo_swiper

/// What the UI tests count on in the mock deck.
struct MockDeckTests {
    /// `testFlaggedPhotoCardShowsNoFlag` swipes to this card to prove flags stay hidden.
    @Test func cardTwelveIsABlurryPhoto() {
        let card = MockFeedBuilder().makeSessionNow(number: 1).cards[12]
        guard case .photo(let item) = card else {
            Issue.record("Card 12 should be a photo")
            return
        }
        #expect(item.id == "s1-i30")
        #expect(item.reviewFlag == .blurry)
    }
}
