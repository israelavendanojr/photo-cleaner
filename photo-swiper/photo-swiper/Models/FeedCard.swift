import Foundation

/// One swipeable card in the feed.
enum FeedCard: Identifiable, Hashable, Sendable {
    case photo(LibraryItem)
    case video(LibraryItem)
    case similar(SimilarGroup)
    case batch(ItemBatch)

    var id: String {
        switch self {
        case .photo(let item), .video(let item): "item-\(item.id)"
        case .similar(let group): group.id
        case .batch(let batch): batch.id
        }
    }

    var items: [LibraryItem] {
        switch self {
        case .photo(let item), .video(let item): [item]
        case .similar(let group): group.items
        case .batch(let batch): batch.items
        }
    }
}

/// A burst of near-identical shots with one suggested keeper.
struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: String
    let items: [LibraryItem]
    let bestID: LibraryItem.ID
    /// Why the best pick won, e.g. "Sharpest, eyes open."
    let reason: String

    var best: LibraryItem { items.first { $0.id == bestID } ?? items[0] }
    var others: [LibraryItem] { items.filter { $0.id != bestID } }
}

/// A group of low-value items cleared or kept together.
struct ItemBatch: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case screenshots, forwarded
    }

    let id: String
    let kind: Kind
    /// Short chip text, e.g. "Screenshots".
    let label: String
    /// Headline, e.g. "14 screenshots from last week".
    let title: String
    let items: [LibraryItem]
}
