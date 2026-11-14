import Foundation
import SwiftData

// The current models, `BristleSchemaV3`. Before changing one, read `BristleSchema.swift`.

/// One item's decision, keyed by `PHAsset.localIdentifier`.
@Model
final class ItemProgress {
    @Attribute(.unique) var itemID: String
    /// `Decision.rawValue`.
    var decisionRaw: String
    var decidedAt: Date
    var sessionNumber: Int
    /// Copied out of `itemData` so totals can be queried.
    var bytes: Int64
    /// `Settlement.rawValue`, nil while open.
    var settlementRaw: String?
    var settledAt: Date?
    /// JSON `LibraryItem`, so carried-over pile items can be shown.
    var itemData: Data
    /// `CleanupCategory.rawValue`, from the card the decision was made on. Nil in rows saved before V2.
    var categoryRaw: String?
    /// JSON `PendingTrim`, for a video kept on the way to being trimmed. Nil otherwise, and in rows saved before V3.
    var trimData: Data?

    init(itemID: String, decisionRaw: String, decidedAt: Date, sessionNumber: Int, bytes: Int64, itemData: Data) {
        self.itemID = itemID
        self.decisionRaw = decisionRaw
        self.decidedAt = decidedAt
        self.sessionNumber = sessionNumber
        self.bytes = bytes
        self.itemData = itemData
    }
}

/// The session in progress. There is at most one.
@Model
final class SessionProgress {
    var number: Int
    var index: Int
    var finished: Bool
    var startedAt: Date
    var updatedAt: Date
    /// JSON `Session`: cards, groups, batches, and item metadata.
    var snapshot: Data
    /// JSON `[SimilarGroup.ID: Set<LibraryItem.ID>]`.
    var marks: Data
    /// JSON `[FeedCard.ID: [LibraryItem.ID: Decision]]` (a batch card's ID is its batch ID). Nil in rows saved before drafts existed.
    var drafts: Data?

    init(number: Int, index: Int, finished: Bool, startedAt: Date, snapshot: Data, marks: Data) {
        self.number = number
        self.index = index
        self.finished = finished
        self.startedAt = startedAt
        updatedAt = startedAt
        self.snapshot = snapshot
        self.marks = marks
    }
}

/// Space cleared in one category by one delete from the pile. The dashboard's history: cleared over
/// time, week over week. Rows are only ever added (and removed by a reset), never edited.
@Model
final class CleanupEvent {
    var id: UUID
    var at: Date
    var count: Int
    var bytes: Int64
    /// `CleanupCategory.rawValue`.
    var categoryRaw: String

    init(id: UUID, at: Date, count: Int, bytes: Int64, categoryRaw: String) {
        self.id = id
        self.at = at
        self.count = count
        self.bytes = bytes
        self.categoryRaw = categoryRaw
    }
}
