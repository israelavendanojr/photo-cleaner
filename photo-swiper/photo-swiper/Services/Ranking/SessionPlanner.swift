import Foundation

/// One item competing for a place in a session.
struct RankCandidate: Hashable, Sendable {
    let id: LibraryItem.ID
    let features: AssetFeatures
}

/// A similar group ready to plan: its members, oldest first, and the keeper.
struct PlannedGroup: Hashable, Sendable {
    let ids: [LibraryItem.ID]
    let bestID: LibraryItem.ID
    let reason: String
}

/// Chooses and orders a session's items from a pool of candidates.
///
/// Ranks the pool, takes the top `limit` items, and gathers screenshots into one batch per calendar
/// week, placed where that week's best-ranked screenshot landed. Similar groups compete as one card,
/// ranked by what clearing all but the keeper would free. A grouped photo never shows as a single
/// card, even when its group waits for a later session. Pure, so it's testable without PhotoKit.
struct SessionPlanner: Sendable {
    enum Slot: Hashable, Sendable {
        case single(LibraryItem.ID)
        /// Screenshots from the calendar week starting at `week`, best ranked first.
        case screenshots(week: Date, ids: [LibraryItem.ID])
        /// Near-identical photos, oldest first, with the one to keep.
        case similar(ids: [LibraryItem.ID], bestID: LibraryItem.ID, reason: String)

        var ids: [LibraryItem.ID] {
            switch self {
            case .single(let id): [id]
            case .screenshots(_, let ids), .similar(let ids, _, _): ids
            }
        }

        var isSimilar: Bool {
            if case .similar = self { true } else { false }
        }
    }

    /// How a similar group scores against single items' `FeedRanker` totals.
    struct GroupWeights: Sendable, Equatable {
        /// Per tenfold of the megabytes the group would clear, like `FeedRanker.Weights.size`.
        var size = 1.0
        /// Per shot beyond the keeper.
        var perExtraShot = 0.3
    }

    var ranker = FeedRanker()
    /// Items per session; every screenshot in a batch and every photo in a similar group counts.
    var limit: Int
    /// Weeks with fewer screenshots than this show them as ordinary cards.
    var minBatch: Int
    /// Screenshots beyond this in one week wait for a later session.
    var maxBatch: Int
    var calendar = Calendar.current
    var groupWeights = GroupWeights()
    /// A session with any similar card shows one within this many cards.
    var similarWithin = 5

    func plan(_ candidates: [RankCandidate], groups: [PlannedGroup] = [], now: Date) -> [Slot] {
        let grouped = Set(groups.flatMap(\.ids))
        let features = Dictionary(candidates.map { ($0.id, $0.features) }, uniquingKeysWith: { first, _ in first })
        let singles = candidates.filter { !grouped.contains($0.id) }.map { Ranked.single($0, ranker.score($0.features, now: now).total) }
        let bundles = groups.compactMap { group in score(group, features).map { Ranked.group(group, $0, newest(group, features)) } }
        let ranked = (singles + bundles).sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id < b.id
        }

        var slots: [Slot] = []
        var slotForWeek: [Date: Int] = [:]
        var count = 0
        for entry in ranked {
            guard count < limit else { break }
            let candidate: RankCandidate
            switch entry {
            case .group(let group, _, _):
                // A group comes whole or waits for a later session.
                guard count + group.ids.count <= limit else { continue }
                slots.append(.similar(ids: group.ids, bestID: group.bestID, reason: group.reason))
                count += group.ids.count
                continue
            case .single(let single, _):
                candidate = single
            }
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

        let flattened = slots.flatMap { slot -> [Slot] in
            if case .screenshots(_, let ids) = slot, ids.count < minBatch {
                return ids.map(Slot.single)
            }
            return [slot]
        }
        return arranged(flattened)
    }

    // MARK: Internals

    private enum Ranked {
        case single(RankCandidate, Double)
        /// A group, its score, and its newest member's date.
        case group(PlannedGroup, Double, Date)

        var score: Double {
            switch self {
            case .single(_, let score), .group(_, let score, _): score
            }
        }

        var createdAt: Date {
            switch self {
            case .single(let candidate, _): candidate.features.createdAt
            case .group(_, _, let newest): newest
            }
        }

        var id: LibraryItem.ID {
            switch self {
            case .single(let candidate, _): candidate.id
            case .group(let group, _, _): group.ids.first ?? ""
            }
        }
    }

    /// Nil when the group can't be shown: a member isn't among the candidates, or the keeper isn't in it.
    private func score(_ group: PlannedGroup, _ features: [LibraryItem.ID: AssetFeatures]) -> Double? {
        guard group.ids.count > 1, group.ids.contains(group.bestID), group.ids.allSatisfy({ features[$0] != nil }) else { return nil }
        let clearable = group.ids.filter { $0 != group.bestID }.reduce(Int64(0)) { $0 + (features[$1]?.bytes ?? 0) }
        let megabytes = Double(max(clearable, 1)) / 1_000_000
        return groupWeights.size * min(max(log10(megabytes), -1), 4) + groupWeights.perExtraShot * Double(group.ids.count - 1)
    }

    private func newest(_ group: PlannedGroup, _ features: [LibraryItem.ID: AssetFeatures]) -> Date {
        group.ids.compactMap { features[$0]?.createdAt }.max() ?? .distantPast
    }

    /// Keeps similar cards apart, and brings the best-ranked one forward if none is near the start.
    private func arranged(_ slots: [Slot]) -> [Slot] {
        var slots = slots
        var i = 1
        while i < slots.count {
            if slots[i].isSimilar, slots[i - 1].isSimilar {
                guard let next = slots[(i + 1)...].firstIndex(where: { !$0.isSimilar }) else {
                    // Nothing left to put between them; this group waits for a later session.
                    slots.remove(at: i)
                    continue
                }
                slots.insert(slots.remove(at: next), at: i)
            }
            i += 1
        }
        if let first = slots.firstIndex(where: \.isSimilar), first >= similarWithin {
            // Its old neighbors aren't similar, and neither is anything before it, so nothing ends up adjacent.
            slots.insert(slots.remove(at: first), at: min(2, similarWithin - 1))
        }
        return slots
    }
}
