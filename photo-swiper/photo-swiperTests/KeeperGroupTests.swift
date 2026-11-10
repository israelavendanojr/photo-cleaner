import Foundation
import Testing
@testable import photo_swiper

/// `KeeperGroup` is computed on top of `SimilarGroup` and `DuplicateGroup`, never stored, so saved
/// decks keep their exact shape (JUN-45, Q-6).
struct KeeperGroupTests {
    /// A deck with a similar and a duplicate card, as encoded before `KeeperGroup` existed
    /// (`JSONEncoder` with sorted keys).
    private static let savedDeck = #"{"cards":[{"similar":{"_0":{"bestID":"B","id":"similar-8ae4764daee1fa10","items":[{"bytes":2000000,"date":821692800,"flags":[],"id":"A","image":{"photoKit":{"localIdentifier":"A"}},"isFavorite":false,"kind":{"photo":{}},"location":"Santa Monica"},{"bytes":2000000,"date":821692800,"flags":[],"id":"B","image":{"photoKit":{"localIdentifier":"B"}},"isFavorite":false,"kind":{"photo":{}},"location":"Santa Monica"}],"maxDistance":0.25,"reason":"Sharpest of the set"}}},{"duplicates":{"_0":{"id":"dup-5022385beceeeec9","items":[{"bytes":2000000,"date":821692800,"flags":[],"id":"C","image":{"photoKit":{"localIdentifier":"C"}},"isFavorite":false,"kind":{"photo":{}},"location":"Santa Monica"},{"bytes":2000000,"date":821692800,"flags":[],"id":"D","image":{"photoKit":{"localIdentifier":"D"}},"isFavorite":false,"kind":{"photo":{}},"location":"Santa Monica"}],"keepID":"C","reason":"Highest resolution"}}},{"photo":{"_0":{"bytes":2000000,"date":821692800,"flags":[],"id":"E","image":{"photoKit":{"localIdentifier":"E"}},"isFavorite":false,"kind":{"photo":{}},"location":"Santa Monica"}}}],"number":4}"#

    private func item(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000), location: "Santa Monica",
                    bytes: 2_000_000, image: .photoKit(localIdentifier: id))
    }

    @Test func aSavedDeckDecodesAndEncodesExactlyAsBefore() throws {
        let session = try JSONDecoder().decode(Session.self, from: Data(Self.savedDeck.utf8))
        #expect(session == Session(number: 4, cards: [
            .similar(SimilarGroup(id: "similar-8ae4764daee1fa10", items: [item("A"), item("B")], bestID: "B",
                                  reason: "Sharpest of the set", maxDistance: 0.25)),
            .duplicates(DuplicateGroup(id: "dup-5022385beceeeec9", items: [item("C"), item("D")], keepID: "C",
                                       reason: "Highest resolution")),
            .photo(item("E")),
        ]))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(decoding: try encoder.encode(session), as: UTF8.self) == Self.savedDeck)
    }

    @Test func bothGroupKindsReadTheSameWay() throws {
        let session = try JSONDecoder().decode(Session.self, from: Data(Self.savedDeck.utf8))
        let groups = session.cards.compactMap(\.keeperGroup)
        #expect(groups.map(\.keeperID) == ["B", "C"])
        #expect(groups.map { $0.others.map(\.id) } == [["A"], ["D"]])
        #expect(groups.map(\.reason) == ["Sharpest of the set", "Highest resolution"])
        #expect(session.cards.last?.keeperGroup == nil)
    }

    @Test func removingKeepsTheGroupUntilTwoAreLeftAndTheKeeperStays() {
        let group = DuplicateGroup(id: "dup-x", items: [item("C"), item("D"), item("F")], keepID: "C", reason: "Highest resolution")
        #expect(group.removing(["F"]) == DuplicateGroup(id: "dup-x", items: [item("C"), item("D")], keepID: "C", reason: "Highest resolution"))
        #expect(group.removing(["D", "F"]) == nil, "One left is no longer a group")
        #expect(group.removing(["C"]) == nil, "Without its keeper the set isn't shown")
    }
}
