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
}
