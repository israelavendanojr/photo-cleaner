import CryptoKit
import Foundation

/// An id for a group from its members alone, whatever their order or the session: the first 8 bytes
/// of a SHA-256 over the sorted ids. Saved marks and drafts key on it, so it must never change.
func stableGroupID(prefix: String, ids: [LibraryItem.ID]) -> String {
    let digest = SHA256.hash(data: Data(ids.sorted().joined(separator: "\n").utf8))
    return prefix + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
}

extension SimilarGroup {
    /// The same members always get the same id, whatever the session, so saved marks keep matching.
    static func stableID(for ids: [LibraryItem.ID]) -> ID { stableGroupID(prefix: "similar-", ids: ids) }
}

extension DuplicateGroup {
    /// Like `SimilarGroup.stableID(for:)`, for a duplicate set.
    static func stableID(for ids: [LibraryItem.ID]) -> ID { stableGroupID(prefix: "dup-", ids: ids) }
}
