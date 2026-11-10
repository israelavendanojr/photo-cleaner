import Foundation

/// A page's duplicate sets and similar groups, and what it took to find them.
struct PageGroups: Sendable {
    /// Keeper first in each. Sets with two or more favorites are dropped.
    var duplicates: [PlannedGroup] = []
    /// Members oldest first. Groups with two or more favorites are dropped.
    var similar: [PlannedGroup] = []
    /// By `SimilarGroup.id`.
    var maxDistance: [SimilarGroup.ID: Double] = [:]
    /// Every similar group found, favorites or not, and the near misses. For `-logSimilarity`.
    var similarResult = SimilarGrouper.Result()
    /// Prints read from the index for this page.
    var duplicatePrintCount = 0
    var similarPrintCount = 0
    var duplicateSeconds = 0.0
    var similarSeconds = 0.0
}

/// Finds a page's duplicate sets among the indexed candidates, then similar groups among the photos
/// left. Only indexed candidates can be grouped: a stale record's print is out of date.
///
/// `uncached` loads every print grouping could use, every page. `GroupingCache` gives the same
/// result while loading only what changed since the last page.
enum PageGrouping {
    /// Stored feature prints for the ids; items without one are left out.
    typealias LoadPrints = @Sendable ([LibraryItem.ID]) async -> [LibraryItem.ID: FeaturePrint]

    static func uncached(
        _ cached: [RankCandidate],
        duplicateGrouper: DuplicateGrouper = DuplicateGrouper(),
        similarGrouper: SimilarGrouper = SimilarGrouper(),
        loadPrints: LoadPrints
    ) async -> PageGroups {
        var page = PageGroups()
        var started = Date.now
        let candidates = duplicateGrouper.candidateIDs(cached)
        if !candidates.isEmpty {
            let prints = await loadPrints(Array(candidates))
            page.duplicates = duplicatePlans(cached.filter { candidates.contains($0.id) }, prints: prints, grouper: duplicateGrouper)
            page.duplicatePrintCount = prints.count
        }
        page.duplicateSeconds = Date.now.timeIntervalSince(started)

        started = .now
        let rest = similarCandidates(cached, excluding: page.duplicates)
        let neighbors = similarGrouper.neighborIDs(rest)
        let prints = await loadPrints(Array(neighbors))
        page.similarPrintCount = prints.count
        page.plan(similar: similarGrouper.group(rest.filter { neighbors.contains($0.id) }, prints: prints), from: rest)
        page.similarSeconds = Date.now.timeIntervalSince(started)
        return page
    }

    /// Duplicate sets ready to plan, keeper first. Sets with two or more favorites are dropped.
    static func duplicatePlans(_ candidates: [RankCandidate], prints: [LibraryItem.ID: FeaturePrint],
                               grouper: DuplicateGrouper = DuplicateGrouper()) -> [PlannedGroup] {
        duplicatePlans(candidates, groups: grouper.group(candidates, prints: prints))
    }

    /// `groups` ready to plan, keeper first. Sets with two or more favorites are dropped.
    static func duplicatePlans(_ candidates: [RankCandidate], groups: [DuplicateGrouper.Group]) -> [PlannedGroup] {
        let features = Dictionary(candidates.map { ($0.id, $0.features) }, uniquingKeysWith: { first, _ in first })
        return groups.compactMap { group in
            let members = group.ids.compactMap { id in features[id].map { RankCandidate(id: id, features: $0) } }
            guard let choice = DuplicatePick.choose(members) else { return nil }
            let ids = [choice.keepID] + group.ids.filter { $0 != choice.keepID }
            return PlannedGroup(ids: ids, bestID: choice.keepID, reason: choice.reason.rawValue)
        }
    }

    /// What similar grouping may use: every candidate not already in a duplicate set.
    static func similarCandidates(_ candidates: [RankCandidate], excluding duplicates: [PlannedGroup]) -> [RankCandidate] {
        let excluded = Set(duplicates.flatMap(\.ids))
        return excluded.isEmpty ? candidates : candidates.filter { !excluded.contains($0.id) }
    }
}

extension PageGroups {
    /// Picks each similar group's best shot. Groups with two or more favorites are dropped, so those
    /// photos compete as singles. `candidates` must include every member, with live favorites.
    mutating func plan(similar result: SimilarGrouper.Result, from candidates: [RankCandidate]) {
        let features = Dictionary(candidates.map { ($0.id, $0.features) }, uniquingKeysWith: { first, _ in first })
        similarResult = result
        for group in result.groups {
            let members = group.ids.compactMap { id in features[id].map { RankCandidate(id: id, features: $0) } }
            guard let choice = BestPick.choose(members) else { continue }
            similar.append(PlannedGroup(ids: group.ids, bestID: choice.bestID, reason: choice.reason.rawValue))
            maxDistance[SimilarGroup.stableID(for: group.ids)] = Double(group.maxDistance)
        }
    }
}
