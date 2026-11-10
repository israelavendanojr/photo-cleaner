import Foundation
import Testing
@testable import photo_swiper

/// The refill reorder: strong cards move ahead, and nothing before `start` ever moves.
struct FrontLoadTests {
    private func item(_ id: String, video bytes: Int64? = nil) -> LibraryItem {
        LibraryItem(id: id, kind: bytes == nil ? .photo : .video(duration: 30), date: Date(timeIntervalSince1970: 1_800_000_000), location: nil,
                    bytes: bytes ?? 1_000_000, image: .bundled("photo-sunset"))
    }

    private func photo(_ id: String) -> FeedCard { .photo(item(id)) }
    private func bigVideo(_ id: String) -> FeedCard { .video(item(id, video: FrontLoad.minVideoBytes)) }
    private func similar(_ id: String) -> FeedCard {
        .similar(SimilarGroup(id: id, items: [item("\(id)1"), item("\(id)2")], bestID: "\(id)1", reason: ""))
    }

    @Test func strongCardsMoveToTheStart() {
        let cards = [photo("A"), photo("B"), similar("S"), bigVideo("V")]
        #expect(FrontLoad.reordered(cards, from: 0) == [similar("S"), bigVideo("V"), photo("A"), photo("B")])
    }

    @Test func theCardOnTopNeverMoves() {
        // The feed reorders from one past the current card, so the card the user is looking at stays put.
        let cards = [photo("A"), photo("B"), similar("S"), bigVideo("V")]
        let reordered = FrontLoad.reordered(cards, from: 1)
        #expect(reordered.first == photo("A"))
        #expect(reordered == [photo("A"), similar("S"), bigVideo("V"), photo("B")])
    }

    @Test func cardsBeforeTheStartStayPut() {
        let cards = [similar("S0"), photo("A"), photo("B"), similar("S"), photo("C")]
        let reordered = FrontLoad.reordered(cards, from: 2)
        #expect(Array(reordered.prefix(2)) == [similar("S0"), photo("A")])
        #expect(Set(reordered.map(\.id)) == Set(cards.map(\.id)))
    }

    @Test func similarSetsAreNeverLeftNextToEachOther() {
        let cards = [photo("A"), similar("S"), similar("T"), photo("B")]
        #expect(FrontLoad.reordered(cards, from: 0) == [similar("S"), photo("A"), similar("T"), photo("B")])
    }

    @Test func aStartPastTheEndChangesNothing() {
        let cards = [photo("A"), similar("S")]
        #expect(FrontLoad.reordered(cards, from: 2) == cards)
    }
}
