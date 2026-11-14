import Foundation

/// The part of a video to keep, in seconds from its start.
struct TrimRange: Codable, Hashable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    var length: TimeInterval { max(end - start, 0) }
}

/// A video waiting in the bin to be replaced by a shorter copy. Nothing in the library changes until the
/// bin is confirmed. Saved as JSON with the video's keep decision (`StoredDecision.trim`), so it survives
/// a relaunch and goes away with the decision: binning the video drops it.
struct PendingTrim: Codable, Hashable, Sendable {
    var range: TrimRange
    /// The video's length when it was trimmed, which the kept fraction is measured against.
    var originalDuration: TimeInterval
    /// The trimmed copy, once it's saved to the library. Set during a confirm, so one that's interrupted
    /// goes straight to the delete next time instead of exporting again.
    var copyID: LibraryItem.ID?

    /// How much of the video is kept, 0...1.
    var keptFraction: Double {
        guard originalDuration > 0 else { return 1 }
        return min(max(range.length / originalDuration, 0), 1)
    }

    /// The copy's size, estimated as the original's size times the kept fraction. Cuts snap to keyframes,
    /// so the real copy can be a little larger.
    func estimatedBytes(from originalBytes: Int64) -> Int64 {
        Int64((Double(originalBytes) * keptFraction).rounded())
    }

    /// Space the trim gives back once the original is deleted.
    func savedBytes(from originalBytes: Int64) -> Int64 {
        max(originalBytes - estimatedBytes(from: originalBytes), 0)
    }
}

/// A video in the bin's Trims section: the original, and how it will be trimmed.
struct TrimmedItem: Identifiable, Hashable, Sendable {
    let item: LibraryItem
    let trim: PendingTrim

    var id: LibraryItem.ID { item.id }
    var savedBytes: Int64 { trim.savedBytes(from: item.bytes) }
}
