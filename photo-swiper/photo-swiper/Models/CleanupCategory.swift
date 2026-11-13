import Foundation

/// What kind of clutter an item was cleared as. The dashboard groups cleared space and suggestions by it,
/// and a focused feed offers only one kind.
///
/// Saved as its raw value (`ItemProgress.categoryRaw`, `CleanupEvent.categoryRaw`), so cases can be added
/// but never renamed.
enum CleanupCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case duplicate
    case similar
    case screenshot
    case video
    case burst
    case photo

    /// The category a decision on `card` files `item` under. Group cards say what they are; a single
    /// card falls back to what the item itself is.
    static func of(_ item: LibraryItem, on card: FeedCard) -> CleanupCategory {
        switch card {
        case .duplicates: .duplicate
        case .similar: .similar
        case .batch(let batch):
            switch batch.kind {
            case .screenshots: .screenshot
            }
        case .photo, .video: inferred(from: item)
        }
    }

    /// The best guess from the item alone, for decisions saved before categories were recorded.
    /// Duplicate and similar can't be told from one item, so those read as a photo.
    static func inferred(from item: LibraryItem) -> CleanupCategory {
        if item.isVideo { return .video }
        if item.flags.contains(.screenshot) || item.features?.isScreenshot == true { return .screenshot }
        if item.features?.isInBurst == true { return .burst }
        return .photo
    }

    /// The same guess from features alone, as the feed builder sees an item.
    static func inferred(from features: AssetFeatures) -> CleanupCategory {
        if features.isVideo { return .video }
        if features.isScreenshot { return .screenshot }
        if features.isInBurst { return .burst }
        return .photo
    }
}

extension FeedCard {
    /// The card belongs in a feed with this focus. A focus by ID matches single cards whose item is in
    /// `only`; with no `only` (the view model can't tell a Live Photo), nothing matches, and new pages
    /// bring the right cards.
    func matches(_ focus: FocusTarget, only: Set<LibraryItem.ID>?) -> Bool {
        switch (focus, self) {
        case (.category(let category), _): matches(category)
        case (.allVideos, .video): true
        case (.livePhotos, .photo(let item)), (.savedForLater, .photo(let item)), (.savedForLater, .video(let item)):
            only?.contains(item.id) == true
        case (.accidental, .photo(let item)): item.reviewFlag == .accidental
        case (.blurry, .photo(let item)): item.reviewFlag == .blurry
        case (.documents, .photo(let item)): item.features?.isUtility == true
        default: false
        }
    }

    /// The card belongs in a feed focused on `category`. Group cards are their group's kind; a single
    /// card is what its item is, so a free user's unbundled duplicate reads as a photo. Videos count only
    /// when large, as the dashboard counts them (`LibraryScan.largeVideoBytes`).
    func matches(_ category: CleanupCategory) -> Bool {
        switch self {
        case .duplicates: category == .duplicate
        case .similar: category == .similar
        case .batch(let batch):
            switch batch.kind {
            case .screenshots: category == .screenshot
            }
        case .video(let item): category == .video && item.bytes >= LibraryScan.largeVideoBytes
        case .photo(let item): CleanupCategory.inferred(from: item) == category
        }
    }
}
