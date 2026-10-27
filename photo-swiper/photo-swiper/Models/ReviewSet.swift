import Foundation

/// The items of one card, gone through one by one in the review deck.
struct ReviewSet: Identifiable, Hashable {
    /// The card's ID, which drafts are saved under.
    let id: FeedCard.ID
    /// Top bar title, e.g. "Screenshots" or "Similar shots".
    let title: String
    let items: [LibraryItem]
    /// Where the review opens.
    let start: Int
    /// The suggested keeper of a similar set, shown with a "Best pick" chip.
    var bestID: LibraryItem.ID?
    /// Why the best pick won, e.g. "Sharpest of the set".
    var reason: String?

    init(batch: ItemBatch) {
        id = batch.id
        title = batch.label
        items = batch.items
        start = 0
    }

    /// The best pick first, then the others as on the card, opening on `startID`.
    init(group: SimilarGroup, startingAt startID: LibraryItem.ID) {
        id = group.id
        title = "Similar shots"
        items = [group.best] + group.others
        start = items.firstIndex { $0.id == startID } ?? 0
        bestID = group.bestID
        reason = group.reason
    }

    /// Nil for single-item cards, which have nothing to go through.
    init?(card: FeedCard, startingAt startID: LibraryItem.ID? = nil) {
        switch card {
        case .batch(let batch): self.init(batch: batch)
        case .similar(let group): self.init(group: group, startingAt: startID ?? group.bestID)
        case .photo, .video: return nil
        }
    }

    /// The order the deck shows items in: those already decided in `draft`, then the rest
    /// starting at `start` and wrapping around. The first undecided one is where it resumes.
    func visitOrder(draft: [LibraryItem.ID: Decision]) -> [LibraryItem] {
        let decided = items.filter { draft[$0.id] != nil }
        let rotated = items[start...] + items[..<start]
        return decided + rotated.filter { draft[$0.id] == nil }
    }
}
