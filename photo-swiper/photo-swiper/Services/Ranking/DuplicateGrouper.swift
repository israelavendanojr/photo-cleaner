import Foundation

/// Finds exact duplicates: the same photo saved more than once, whenever each copy was saved.
///
/// Three checks, cheapest first. Candidate pairs come from the `DHash`: a 64-bit hash is split into
/// four 16-bit bands, and two hashes within `maxHamming` (at most 3) bits must agree exactly on at
/// least one band, so bucketing by band finds every close pair without comparing all pairs. A pair
/// must then have the same aspect ratio, from the pixel size, and finally feature prints almost on
/// top of each other. Prints are only loaded for photos in a candidate pair. Confirmed pairs are
/// joined into groups. No time window: copies saved years apart still match.
///
/// Same eligibility as `SimilarGrouper` (photos only; no videos, screenshots, or utility shots).
/// Pure, and the distance is injectable, so tests run on made-up hashes and vectors without Vision.
struct DuplicateGrouper: Sendable {
    struct Tunables: Sendable, Equatable {
        /// Most hash bits two copies may differ by. Recompression and resizing flip a few; different
        /// photos land around 32 apart.
        var maxHamming = 3
        /// Largest relative difference in width over height.
        var maxAspectDifference = 0.01
        /// Farthest apart two copies' prints may be. Re-encoded copies of one image measure a few
        /// hundredths; similar shots run 0.2–0.45 (`SimilarGrouper` groups below 0.45).
        var maxDistance: Float = 0.1
        /// Bigger groups are cut into runs of near-equal size, so one fits in a session.
        var maxSize = 10
        /// A hash band shared by more photos than this says little (flat or dark frames all look
        /// alike there), so it isn't used to find pairs. Pairs can still meet on another band.
        var maxBucket = 256
    }

    struct Group: Hashable, Sendable {
        /// Oldest first.
        let ids: [LibraryItem.ID]
        /// Largest print distance among the confirmed pairs.
        let maxDistance: Float
    }

    var tunables = Tunables()
    var distance: @Sendable (FeaturePrint, FeaturePrint) -> Float = { FeaturePrint.euclidean($0, $1) }

    /// Like similar shots, plus a hash and a pixel size to compare.
    static func isEligible(_ features: AssetFeatures) -> Bool {
        SimilarGrouper.isEligible(features) && features.dHash != nil && features.aspectRatio != nil
    }

    /// Candidates in at least one pair that passes the hash and aspect checks. Only these need prints.
    func candidateIDs(_ candidates: [RankCandidate]) -> Set<LibraryItem.ID> {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) })
        return Set(pairs(eligible).flatMap { [eligible[$0.0].id, eligible[$0.1].id] })
    }

    func group(_ candidates: [RankCandidate], prints: [LibraryItem.ID: FeaturePrint]) -> [Group] {
        group(candidates, hasPrint: { prints[$0] != nil }) { a, b in
            guard let pa = prints[a], let pb = prints[b] else { return nil }
            return distance(pa, pb)
        }
    }

    /// The pairs `group` compares, older first in each: eligible candidates with a print whose hashes
    /// and shapes match. Which pairs those are depends on every candidate passed, since crowded hash
    /// bands are skipped.
    func pairIDs(_ candidates: [RankCandidate], hasPrint: (LibraryItem.ID) -> Bool) -> [(LibraryItem.ID, LibraryItem.ID)] {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) && hasPrint($0.id) })
        return pairs(eligible).map { (eligible[$0.0].id, eligible[$0.1].id) }
    }

    /// `group(_:prints:)` with print distances from elsewhere, e.g. remembered from an earlier page.
    /// `pairDistance` is asked only for pairs `pairIDs` returns; nil skips the pair.
    func group(_ candidates: [RankCandidate], hasPrint: (LibraryItem.ID) -> Bool,
               pairDistance: (LibraryItem.ID, LibraryItem.ID) -> Float?) -> [Group] {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) && hasPrint($0.id) })
        var parent = Array(eligible.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        var widest: [Int: Float] = [:]
        var confirmed: [(Int, Int, Float)] = []
        for (a, b) in pairs(eligible) {
            guard let d = pairDistance(eligible[a].id, eligible[b].id), d <= tunables.maxDistance else { continue }
            confirmed.append((a, b, d))
            let ra = root(a), rb = root(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for (a, _, d) in confirmed {
            let r = root(a)
            widest[r] = max(widest[r] ?? 0, d)
        }

        // Members stay oldest first, since `eligible` is.
        var members: [Int: [Int]] = [:]
        for i in eligible.indices { members[root(i), default: []].append(i) }
        let groups = members.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }.flatMap { root, indices in
            // A group over the size limit is cut into runs of near-equal length.
            GroupingUtil.balancedChunks(indices, max: tunables.maxSize).map { chunk in
                Group(ids: chunk.map { eligible[$0].id }, maxDistance: widest[root] ?? 0)
            }
        }
        return groups
    }

    // MARK: Internals

    /// Index pairs, each once, whose hashes are within `maxHamming` and whose aspect ratios match.
    private func pairs(_ eligible: [RankCandidate]) -> [(Int, Int)] {
        let hashes = eligible.map { $0.features.dHash ?? 0 }
        let aspects = eligible.map { $0.features.aspectRatio ?? 0 }
        let bands = 4
        func band(_ hash: UInt64, _ k: Int) -> UInt16 { UInt16(truncatingIfNeeded: hash >> (16 * k)) }

        let buckets: [[UInt16: [Int]]] = (0..<bands).map { k in
            Dictionary(grouping: hashes.indices, by: { band(hashes[$0], k) })
        }
        func isUsable(_ k: Int, _ value: UInt16) -> Bool { (buckets[k][value]?.count ?? 0) <= tunables.maxBucket }

        var result: [(Int, Int)] = []
        for k in 0..<bands {
            for bucket in buckets[k].values where bucket.count > 1 && bucket.count <= tunables.maxBucket {
                for (n, a) in bucket.enumerated() {
                    for b in bucket.dropFirst(n + 1) {
                        // Each pair once: on the first usable band the two agree on.
                        let foundEarlier = (0..<k).contains { j in
                            band(hashes[a], j) == band(hashes[b], j) && isUsable(j, band(hashes[a], j))
                        }
                        guard !foundEarlier, DHash.distance(hashes[a], hashes[b]) <= tunables.maxHamming,
                              Self.aspectsMatch(aspects[a], aspects[b], within: tunables.maxAspectDifference) else { continue }
                        result.append((a, b))
                    }
                }
            }
        }
        return result
    }

    private static func aspectsMatch(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
        abs(a - b) / max(a, b) <= tolerance
    }

    private func sorted(_ candidates: [RankCandidate]) -> [RankCandidate] {
        candidates.sorted(by: RankCandidate.oldestFirst)
    }
}
