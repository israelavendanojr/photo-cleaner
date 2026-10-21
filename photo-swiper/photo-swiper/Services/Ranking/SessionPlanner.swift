import Foundation

/// One item competing for a place in a session.
struct RankCandidate: Hashable, Sendable {
    let id: LibraryItem.ID
    let features: AssetFeatures
}

/// Chooses and orders a session's items from a pool of candidates.
///
/// Ranks the pool, takes the top `limit` items, and gathers screenshots into one batch per calendar
/// week, placed where that week's best-ranked screenshot landed. Pure, so it's testable without PhotoKit.
struct SessionPlanner: Sendable {
    enum Slot: Hashable, Sendable {
        case single(LibraryItem.ID)
        /// Screenshots from the calendar week starting at `week`, best ranked first.
        case screenshots(week: Date, ids: [LibraryItem.ID])

        var ids: [LibraryItem.ID] {
            switch self {
            case .single(let id): [id]
            case .screenshots(_, let ids): ids
            }
        }
    }

    var ranker = FeedRanker()
    /// Items per session; every screenshot in a batch counts.
    var limit: Int
    /// Weeks with fewer screenshots than this show them as ordinary cards.
    var minBatch: Int
    /// Screenshots beyond this in one week wait for a later session.
    var maxBatch: Int
    var calendar = Calendar.current

    func plan(_ candidates: [RankCandidate], now: Date) -> [Slot] {
        let ranked = candidates
            .map { (candidate: $0, score: ranker.score($0.features, now: now).total) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.candidate.features.createdAt != b.candidate.features.createdAt {
                    return a.candidate.features.createdAt > b.candidate.features.createdAt
                }
                return a.candidate.id < b.candidate.id
            }
            .map(\.candidate)

        var slots: [Slot] = []
        var slotForWeek: [Date: Int] = [:]
        var count = 0
        for candidate in ranked {
            guard count < limit else { break }
            let features = candidate.features
            guard features.isScreenshot else {
                slots.append(.single(candidate.id))
                count += 1
                continue
            }
            let week = calendar.dateInterval(of: .weekOfYear, for: features.createdAt)?.start ?? features.createdAt
            if let index = slotForWeek[week] {
                let ids = slots[index].ids
                guard ids.count < maxBatch else { continue }
                slots[index] = .screenshots(week: week, ids: ids + [candidate.id])
            } else {
                slotForWeek[week] = slots.count
                slots.append(.screenshots(week: week, ids: [candidate.id]))
            }
            count += 1
        }

        return slots.flatMap { slot -> [Slot] in
            if case .screenshots(_, let ids) = slot, ids.count < minBatch {
                return ids.map(Slot.single)
            }
            return [slot]
        }
    }
}
