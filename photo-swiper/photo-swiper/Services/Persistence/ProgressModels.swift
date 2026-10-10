import Foundation
import SwiftData

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
    /// JSON `[ItemBatch.ID: [LibraryItem.ID: Decision]]`. Nil in rows saved before drafts existed.
    var drafts: Data?

    init(number: Int, index: Int, finished: Bool, startedAt: Date, snapshot: Data, marks: Data) {
        self.number = number
        self.index = index
        self.finished = finished
        self.startedAt = startedAt
        self.updatedAt = startedAt
        self.snapshot = snapshot
        self.marks = marks
    }
}
