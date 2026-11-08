import Foundation

/// One swipeable card in the feed.
enum FeedCard: Identifiable, Hashable, Sendable, Codable {
    case photo(LibraryItem)
    case video(LibraryItem)
    case similar(SimilarGroup)
    case batch(ItemBatch)
    /// Copies of one photo. Added after decks were first saved; old decks without it still decode.
    case duplicates(DuplicateGroup)

    /// The single-item card for a photo or video.
    init(item: LibraryItem) {
        self = item.isVideo ? .video(item) : .photo(item)
    }

    var id: String {
        switch self {
        case .photo(let item), .video(let item): "item-\(item.id)"
        case .similar(let group): group.id
        case .batch(let batch): batch.id
        case .duplicates(let group): group.id
        }
    }

    var items: [LibraryItem] {
        switch self {
        case .photo(let item), .video(let item): [item]
        case .similar(let group): group.items
        case .batch(let batch): batch.items
        case .duplicates(let group): group.items
        }
    }

    /// The tier feature this card needs. Nil for single cards, which everyone gets.
    var feature: TierFeature? {
        switch self {
        case .photo, .video: nil
        case .similar: .similarShots
        case .duplicates: .duplicates
        case .batch(let batch):
            switch batch.kind {
            case .screenshots: .screenshotBatches
            }
        }
    }

    /// Itself when `enabled` allows it, otherwise a single card per item, in the bundle's order.
    func unbundled(unless enabled: Set<TierFeature>) -> [FeedCard] {
        guard let feature, !enabled.contains(feature) else { return [self] }
        return items.map(FeedCard.init(item:))
    }
}

/// A burst of near-identical shots with one suggested keeper.
struct SimilarGroup: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let items: [LibraryItem]
    let bestID: LibraryItem.ID
    /// Why the best pick won, e.g. "Sharpest of the set".
    let reason: String
    /// Largest feature-print distance between two members, for tuning. Nil for mock groups.
    var maxDistance: Double? = nil

    var best: LibraryItem { items.first { $0.id == bestID } ?? items[0] }
    var others: [LibraryItem] { items.filter { $0.id != bestID } }
}

/// The same photo saved more than once, with the copy to keep.
struct DuplicateGroup: Identifiable, Hashable, Sendable, Codable {
    let id: String
    /// The keeper first, then the other copies oldest first.
    let items: [LibraryItem]
    let keepID: LibraryItem.ID
    /// Why that copy is the keeper, e.g. "Highest resolution".
    let reason: String

    var keep: LibraryItem { items.first { $0.id == keepID } ?? items[0] }
    var others: [LibraryItem] { items.filter { $0.id != keepID } }
}

/// A group of low-value items cleared or kept together.
struct ItemBatch: Identifiable, Hashable, Sendable, Codable {
    enum Kind: Hashable, Sendable, Codable {
        case screenshots
    }

    let id: String
    let kind: Kind
    /// Short chip text, e.g. "Screenshots".
    let label: String
    /// Headline, e.g. "14 screenshots from last week".
    let title: String
    let items: [LibraryItem]
}
