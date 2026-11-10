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

    /// The similar or duplicate group on this card, if it is one.
    var keeperGroup: (any KeeperGroup)? {
        switch self {
        case .similar(let group): group
        case .duplicates(let group): group
        case .photo, .video, .batch: nil
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

/// Near-identical photos with one to keep: similar shots, or copies of one photo. The rest can go.
protocol KeeperGroup: Identifiable, Hashable, Sendable where ID == String {
    var items: [LibraryItem] { get }
    /// The one to keep.
    var keeperID: LibraryItem.ID { get }
    /// Why that one, e.g. "Sharpest of the set".
    var reason: String { get }
    /// This group with only `items`, keeping its id, keeper, and reason.
    func with(items: [LibraryItem]) -> Self
}

extension KeeperGroup {
    var others: [LibraryItem] { items.filter { $0.id != keeperID } }

    /// This group without `ids`, or nil once fewer than two are left or the keeper is gone.
    func removing(_ ids: Set<LibraryItem.ID>) -> Self? {
        let rest = items.filter { !ids.contains($0.id) }
        guard rest.count > 1, !ids.contains(keeperID) else { return nil }
        return with(items: rest)
    }
}

/// A burst of near-identical shots with one suggested keeper, which is always one of `items`.
struct SimilarGroup: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let items: [LibraryItem]
    let bestID: LibraryItem.ID
    /// Why the best pick won, e.g. "Sharpest of the set".
    let reason: String
    /// Largest feature-print distance between two members, for tuning. Nil for mock groups.
    var maxDistance: Double? = nil

    init(id: String, items: [LibraryItem], bestID: LibraryItem.ID, reason: String, maxDistance: Double? = nil) {
        precondition(items.contains { $0.id == bestID }, "A similar group must contain its best shot")
        self.id = id
        self.items = items
        self.bestID = bestID
        self.reason = reason
        self.maxDistance = maxDistance
    }

    /// A saved group without its best shot is unreadable rather than shown with the wrong one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([LibraryItem].self, forKey: .items)
        let bestID = try container.decode(LibraryItem.ID.self, forKey: .bestID)
        guard items.contains(where: { $0.id == bestID }) else {
            throw DecodingError.dataCorruptedError(forKey: .bestID, in: container, debugDescription: "The best shot isn't in the group")
        }
        self.init(id: try container.decode(String.self, forKey: .id), items: items, bestID: bestID,
                  reason: try container.decode(String.self, forKey: .reason),
                  maxDistance: try container.decodeIfPresent(Double.self, forKey: .maxDistance))
    }

    // Every way to make a group checks the best shot is in it.
    var best: LibraryItem { items.first { $0.id == bestID }! }
}

extension SimilarGroup: KeeperGroup {
    var keeperID: LibraryItem.ID { bestID }

    func with(items: [LibraryItem]) -> SimilarGroup {
        SimilarGroup(id: id, items: items, bestID: bestID, reason: reason, maxDistance: maxDistance)
    }
}

/// The same photo saved more than once, with the copy to keep, which is always one of `items`.
struct DuplicateGroup: Identifiable, Hashable, Sendable, Codable {
    let id: String
    /// The keeper first, then the other copies oldest first.
    let items: [LibraryItem]
    let keepID: LibraryItem.ID
    /// Why that copy is the keeper, e.g. "Highest resolution".
    let reason: String

    init(id: String, items: [LibraryItem], keepID: LibraryItem.ID, reason: String) {
        precondition(items.contains { $0.id == keepID }, "A duplicate set must contain its keeper")
        self.id = id
        self.items = items
        self.keepID = keepID
        self.reason = reason
    }

    /// A saved set without its keeper is unreadable rather than shown with the wrong one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decode([LibraryItem].self, forKey: .items)
        let keepID = try container.decode(LibraryItem.ID.self, forKey: .keepID)
        guard items.contains(where: { $0.id == keepID }) else {
            throw DecodingError.dataCorruptedError(forKey: .keepID, in: container, debugDescription: "The keeper isn't in the set")
        }
        self.init(id: try container.decode(String.self, forKey: .id), items: items, keepID: keepID,
                  reason: try container.decode(String.self, forKey: .reason))
    }

    // Every way to make a set checks the keeper is in it.
    var keep: LibraryItem { items.first { $0.id == keepID }! }
}

extension DuplicateGroup: KeeperGroup {
    var keeperID: LibraryItem.ID { keepID }

    func with(items: [LibraryItem]) -> DuplicateGroup {
        DuplicateGroup(id: id, items: items, keepID: keepID, reason: reason)
    }
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
