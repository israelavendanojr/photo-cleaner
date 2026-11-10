import Foundation

/// Pieces `SimilarGrouper` and `DuplicateGrouper` share.
enum GroupingUtil {
    /// `items` cut into consecutive runs of near-equal length, none longer than `max`. A run of 17
    /// with `max` 8 becomes 6, 6, 5 rather than 8, 8, 1.
    static func balancedChunks<T>(_ items: [T], max: Int) -> [[T]] {
        let count = (items.count + max - 1) / max
        var chunks: [[T]] = []
        var start = 0
        for k in 0..<count {
            let size = items.count / count + (k < items.count % count ? 1 : 0)
            chunks.append(Array(items[start..<start + size]))
            start += size
        }
        return chunks
    }
}

extension RankCandidate {
    /// Oldest first; ties by id so a result doesn't depend on input order.
    static func oldestFirst(_ a: RankCandidate, _ b: RankCandidate) -> Bool {
        a.features.createdAt != b.features.createdAt ? a.features.createdAt < b.features.createdAt : a.id < b.id
    }
}
