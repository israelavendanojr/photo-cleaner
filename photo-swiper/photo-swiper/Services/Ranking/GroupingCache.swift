import Foundation

/// `PageGrouping.uncached`, remembering between pages what doesn't change, so a page reads only the
/// prints it hasn't seen. The result is always exactly what `uncached` would return.
///
/// From one page to the next mostly the excluded set grows (decided and dealt items), and grouping
/// has to run without them, since a group that loses a member can regroup differently. So nothing
/// is filtered after the fact; instead each grouper's work is split where it provably doesn't interact:
/// - Similar shots: `SimilarGrouper.components` splits the candidates where a group can't reach
///   across. Each component's result is kept by its exact members and reused while they're unchanged;
///   only components that changed load prints and group again.
/// - Duplicates: candidate pairs are found again every page from hashes alone, since which pairs are
///   compared depends on every candidate. Only each pair's print distance is kept.
///
/// Prints themselves are dropped as soon as a page's groups are found. Everything is forgotten when
/// the index changes (`FeatureIndexReading.generation`) or favorites are skipped differently. Keeper
/// picks are made fresh every page, since favorites are read live.
actor GroupingCache {
    struct Key: Hashable, Sendable {
        var generation: Int
        var skipFavorites: Bool
    }

    private struct Pair: Hashable {
        /// The older of the two first, as `DuplicateGrouper` orders them.
        let first: LibraryItem.ID
        let second: LibraryItem.ID
    }

    let duplicateGrouper: DuplicateGrouper
    let similarGrouper: SimilarGrouper
    private var key: Key?
    /// Each similar component's result, by its members' ids. Only the last page's.
    private var components: [String: SimilarGrouper.Result] = [:]
    /// Whether each duplicate candidate has a stored print.
    private var hasPrint: [LibraryItem.ID: Bool] = [:]
    /// Print distance of each duplicate pair compared. Only the last page's.
    private var distances: [Pair: Float] = [:]

    init(duplicateGrouper: DuplicateGrouper = DuplicateGrouper(), similarGrouper: SimilarGrouper = SimilarGrouper()) {
        self.duplicateGrouper = duplicateGrouper
        self.similarGrouper = similarGrouper
    }

    func groups(_ cached: [RankCandidate], key: Key, loadPrints: PageGrouping.LoadPrints) async -> PageGroups {
        if key != self.key {
            self.key = key
            components = [:]
            hasPrint = [:]
            distances = [:]
        }
        var page = PageGroups()
        var started = Date.now
        page.duplicates = await duplicates(cached, page: &page, loadPrints: loadPrints)
        page.duplicateSeconds = Date.now.timeIntervalSince(started)

        started = .now
        let rest = PageGrouping.similarCandidates(cached, excluding: page.duplicates)
        page.plan(similar: await similar(rest, page: &page, loadPrints: loadPrints), from: rest)
        page.similarSeconds = Date.now.timeIntervalSince(started)
        return page
    }

    // MARK: Internals

    private func duplicates(_ cached: [RankCandidate], page: inout PageGroups, loadPrints: PageGrouping.LoadPrints) async -> [PlannedGroup] {
        let candidates = duplicateGrouper.candidateIDs(cached)
        hasPrint = hasPrint.filter { candidates.contains($0.key) }
        guard !candidates.isEmpty else {
            distances = [:]
            return []
        }
        let subset = cached.filter { candidates.contains($0.id) }

        // Which candidates have a print decides which pairs are compared, so learn that first.
        var prints: [LibraryItem.ID: FeaturePrint] = [:]
        let unknown = candidates.filter { hasPrint[$0] == nil }
        if !unknown.isEmpty {
            prints = await loadPrints(Array(unknown))
            for id in unknown { hasPrint[id] = prints[id] != nil }
        }
        let known = hasPrint
        let printed = { (id: LibraryItem.ID) in known[id] == true }

        let pairs = duplicateGrouper.pairIDs(subset, hasPrint: printed).map { Pair(first: $0.0, second: $0.1) }
        let unmeasured = pairs.filter { distances[$0] == nil }
        let missing = Set(unmeasured.flatMap { [$0.first, $0.second] }).filter { prints[$0] == nil }
        if !missing.isEmpty {
            prints.merge(await loadPrints(Array(missing))) { first, _ in first }
        }
        for pair in unmeasured {
            guard let a = prints[pair.first], let b = prints[pair.second] else { continue }
            distances[pair] = duplicateGrouper.distance(a, b)
        }
        let current = Set(pairs)
        distances = distances.filter { current.contains($0.key) }
        page.duplicatePrintCount = prints.count

        let measured = distances
        let groups = duplicateGrouper.group(subset, hasPrint: printed) { measured[Pair(first: $0, second: $1)] }
        return PageGrouping.duplicatePlans(subset, groups: groups)
    }

    private func similar(_ candidates: [RankCandidate], page: inout PageGroups, loadPrints: PageGrouping.LoadPrints) async -> SimilarGrouper.Result {
        let parts = similarGrouper.components(candidates)
        let keys = parts.map { $0.map(\.id).joined(separator: "\n") }
        var results: [String: SimilarGrouper.Result] = [:]
        var stale: [Int] = []
        for (i, key) in keys.enumerated() {
            if let result = components[key] { results[key] = result } else { stale.append(i) }
        }
        if !stale.isEmpty {
            let prints = await loadPrints(stale.flatMap { parts[$0].map(\.id) })
            page.similarPrintCount = prints.count
            for i in stale { results[keys[i]] = similarGrouper.group(parts[i], prints: prints) }
        }
        components = results
        return similarGrouper.merge(keys.compactMap { results[$0] }, of: candidates)
    }
}
