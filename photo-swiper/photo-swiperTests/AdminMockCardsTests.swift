import Foundation
import Testing
@testable import photo_swiper

/// Admin Tools' randomized mock cards.
struct AdminMockCardsTests {
    private func cards(_ kind: AdminMockKind, count: Int = 40) -> [FeedCard] {
        var rng = SeededGenerator(seed: 7)
        return (0..<count).map { _ in AdminMockCards.card(kind, using: &rng) }
    }

    @Test(arguments: AdminMockKind.allCases)
    func everyCardIsMarkedAsAMock(_ kind: AdminMockKind) {
        for card in cards(kind) {
            #expect(card.isAdminMock)
            #expect(card.items.allSatisfy { $0.id.hasPrefix(AdminMockCards.idPrefix) })
            #expect(Set(card.items.map(\.id)).count == card.items.count, "No item twice")
        }
    }

    @Test func eachCardHasItsOwnIDs() {
        var rng = SeededGenerator(seed: 1)
        let a = AdminMockCards.card(.similar, using: &rng)
        let b = AdminMockCards.card(.similar, using: &rng)
        #expect(a.id != b.id)
        #expect(Set(a.items.map(\.id)).isDisjoint(with: b.items.map(\.id)))
    }

    @Test func photosAndVideosAreTheRightKind() {
        for card in cards(.photo) {
            guard case .photo(let item) = card else { Issue.record("Not a photo card"); continue }
            #expect(!item.isVideo)
        }
        for card in cards(.video) {
            guard case .video(let item) = card, let duration = item.duration else { Issue.record("Not a video card"); continue }
            #expect((3...(25 * 60)).contains(duration))
        }
    }

    @Test func similarSetsVaryInSizeAndPick() {
        var sizes = Set<Int>()
        var pickPositions = Set<Int>()
        for card in cards(.similar) {
            guard case .similar(let group) = card else { Issue.record("Not a similar card"); continue }
            #expect(AdminMockCards.similarCounts.contains(group.items.count))
            if let position = group.items.firstIndex(where: { $0.id == group.bestID }) {
                pickPositions.insert(position)
            } else {
                Issue.record("The best pick isn't in the set")
            }
            #expect(!group.reason.isEmpty)
            sizes.insert(group.items.count)
        }
        #expect(sizes.count > 3, "Set sizes are randomized")
        #expect(pickPositions.count > 1, "The best pick isn't always the first shot")
    }

    @Test func duplicatesKeepTheLargestCopyFirst() {
        for card in cards(.duplicates) {
            guard case .duplicates(let group) = card else { Issue.record("Not a duplicates card"); continue }
            #expect(AdminMockCards.duplicateCounts.contains(group.items.count))
            #expect(group.items.first?.id == group.keepID)
            #expect(group.others.allSatisfy { $0.bytes < group.keep.bytes })
            #expect(group.others.map(\.date) == group.others.map(\.date).sorted(), "Others oldest first")
        }
    }

    @Test func screenshotBatchesTitleTheirCount() {
        var counts = Set<Int>()
        for card in cards(.screenshots) {
            guard case .batch(let batch) = card else { Issue.record("Not a batch card"); continue }
            #expect(AdminMockCards.screenshotCounts.contains(batch.items.count))
            #expect(batch.title.hasPrefix("\(batch.items.count) screenshots from "))
            #expect(batch.items.allSatisfy { $0.flags.contains(.screenshot) })
            counts.insert(batch.items.count)
        }
        #expect(counts.count > 3, "Batch sizes are randomized")
    }

    @Test func theRegularDeckIsNotAMock() {
        let cards = MockFeedBuilder().makeSessionNow(number: 1).cards
        #expect(cards.allSatisfy { !$0.isAdminMock })
    }
}
