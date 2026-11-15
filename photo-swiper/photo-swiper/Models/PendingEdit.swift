import Foundation

/// The part of a video to keep, in seconds from its start.
struct TrimRange: Codable, Hashable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    var length: TimeInterval { max(end - start, 0) }
}

/// How hard a video is compressed (JUN-50). The settings for each level live in one config, so they can
/// be tuned; only the level is saved with an edit.
enum CompressionLevel: String, Codable, CaseIterable, Sendable {
    case light
    case balanced
    case max

    var title: String {
        switch self {
        case .light: "Light"
        case .balanced: "Balanced"
        case .max: "Max"
        }
    }
}

/// A video waiting in the bin to be replaced by an edited copy: shorter (a trim), smaller (a compression
/// level), or both. Nothing in the library changes until the bin is confirmed, and then the video is
/// exported once with every change applied. Saved as JSON with the video's keep decision
/// (`StoredDecision.edit`), so it survives a relaunch and goes away with the decision: binning the video
/// drops it. An edit with neither a trim nor a level isn't an edit, and is never saved (`isEmpty`).
///
/// It was `PendingTrim` before JUN-50 and keeps that JSON: the same keys, with every new field optional,
/// so a trim saved by an older build loads as a trim-only edit.
struct PendingEdit: Codable, Hashable, Sendable {
    /// The part to keep, or nil for the whole video.
    var range: TrimRange?
    /// The video's length when it was edited, which the kept fraction is measured against.
    var originalDuration: TimeInterval
    /// Nil leaves the quality alone.
    var compression: CompressionLevel?
    /// The copy's size as the viewer estimated it from the video's bitrate, when it's compressed. Nil for
    /// a trim alone, whose size is the original's times the kept fraction.
    var compressedBytes: Int64?
    /// The edited copy, once it's saved to the library. Set during a confirm, so one that's interrupted
    /// goes straight to the delete next time instead of exporting again.
    var copyID: LibraryItem.ID?

    init(range: TrimRange? = nil, originalDuration: TimeInterval, compression: CompressionLevel? = nil,
         compressedBytes: Int64? = nil, copyID: LibraryItem.ID? = nil) {
        self.range = range
        self.originalDuration = originalDuration
        self.compression = compression
        self.compressedBytes = compressedBytes
        self.copyID = copyID
    }

    var isTrimmed: Bool { range != nil }
    var isCompressed: Bool { compression != nil }
    /// Neither trimmed nor compressed: nothing to do, so it's removed rather than saved.
    var isEmpty: Bool { !isTrimmed && !isCompressed }

    /// The copy's length.
    var newDuration: TimeInterval { range?.length ?? originalDuration }

    /// How much of the video is kept, 0...1.
    var keptFraction: Double {
        guard let range, originalDuration > 0 else { return 1 }
        return min(max(range.length / originalDuration, 0), 1)
    }

    /// The copy's size. A trim alone is the original's size times the kept fraction; cuts snap to
    /// keyframes, so the real copy can be a little larger. A compressed copy uses the viewer's estimate,
    /// never more than the trim alone would leave.
    func estimatedBytes(from originalBytes: Int64) -> Int64 {
        let trimmed = Int64((Double(originalBytes) * keptFraction).rounded())
        guard isCompressed, let compressedBytes else { return trimmed }
        return min(max(compressedBytes, 0), trimmed)
    }

    /// Space the edit gives back once the original is deleted.
    func savedBytes(from originalBytes: Int64) -> Int64 {
        max(originalBytes - estimatedBytes(from: originalBytes), 0)
    }
}

/// A video in the bin's Edits section: the original, and how it will be edited.
struct EditedItem: Identifiable, Hashable, Sendable {
    let item: LibraryItem
    let edit: PendingEdit

    var id: LibraryItem.ID { item.id }
    var newBytes: Int64 { edit.estimatedBytes(from: item.bytes) }
    var savedBytes: Int64 { edit.savedBytes(from: item.bytes) }
}
