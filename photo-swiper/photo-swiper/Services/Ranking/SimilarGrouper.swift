import Foundation

/// Finds sets of near-identical photos: frames of one burst, or shots taken moments apart that
/// look alike.
///
/// Only photos with a stored feature print are grouped, so unindexed items never are. Videos,
/// screenshots, and utility shots are left out. Shots are only compared with ones taken around the
/// same time, and a shot joins a group only if it's close to the group's first shot (its seed), not
/// just to its latest one, so a slow pan can't drift into one long group. Pure, and the distance is
/// injectable, so tests run on made-up vectors without Vision.
struct SimilarGrouper: Sendable {
    struct Tunables: Sendable, Equatable {
        /// Longest wait between consecutive shots of one group.
        var maxGap: TimeInterval = 90
        /// Longest time from a group's first shot to its last.
        var maxSpan: TimeInterval = 5 * 60
        /// Farthest a shot can be from the group's seed. Revision 2 prints are about unit length, so
        /// distances run from 0 to roughly 1.4.
        var maxDistance: Float = 0.45
        var sizes: ClosedRange<Int> = 2...8
        /// Pairs this far past `maxDistance` are reported as near misses, for tuning.
        var nearMissMargin: Float = 0.15
    }

    struct Group: Hashable, Sendable {
        /// Oldest first.
        let ids: [LibraryItem.ID]
        /// Largest distance between any two members.
        let maxDistance: Float
        /// Seconds from the first shot to the last.
        let span: TimeInterval
        /// From one burst rather than from time and looks.
        let isBurst: Bool
    }

    /// A pair that was close in time but just too far apart in looks to group.
    struct NearMiss: Hashable, Sendable {
        let seed: LibraryItem.ID
        let other: LibraryItem.ID
        let distance: Float
        let gap: TimeInterval
    }

    struct Result: Sendable {
        var groups: [Group] = []
        var nearMisses: [NearMiss] = []
    }

    var tunables = Tunables()
    var distance: @Sendable (FeaturePrint, FeaturePrint) -> Float = { FeaturePrint.euclidean($0, $1) }

    /// Photos only: no videos, screenshots, or utility shots. Unknown utility (Vision failed) is allowed.
    static func isEligible(_ features: AssetFeatures) -> Bool {
        !features.isVideo && !features.isScreenshot && features.isUtility != true
    }

    /// Candidates that could end up in a group: eligible photos that share a burst or have another
    /// within `maxGap`. Only these need their feature prints loaded.
    func neighborIDs(_ candidates: [RankCandidate]) -> Set<LibraryItem.ID> {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) })
        var ids: Set<LibraryItem.ID> = []
        for (previous, next) in zip(eligible, eligible.dropFirst())
        where next.features.createdAt.timeIntervalSince(previous.features.createdAt) <= tunables.maxGap {
            ids.insert(previous.id)
            ids.insert(next.id)
        }
        for frames in Dictionary(grouping: eligible.filter { $0.features.burstID != nil }, by: { $0.features.burstID }).values
        where frames.count > 1 {
            ids.formUnion(frames.map(\.id))
        }
        return ids
    }

    func group(_ candidates: [RankCandidate], prints: [LibraryItem.ID: FeaturePrint]) -> Result {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) && prints[$0.id] != nil })
        var result = Result()
        var grouped: Set<LibraryItem.ID> = []

        // Frames of one burst belong together whatever they look like.
        let bursts = Dictionary(grouping: eligible.filter { $0.features.burstID != nil }, by: { $0.features.burstID })
        for frames in bursts.values where frames.count >= tunables.sizes.lowerBound {
            // A burst over the size limit is cut into runs of near-equal length.
            for chunk in GroupingUtil.balancedChunks(sorted(frames), max: tunables.sizes.upperBound) {
                result.groups.append(makeGroup(chunk, prints: prints, isBurst: true))
                grouped.formUnion(chunk.map(\.id))
            }
        }

        // Everything else: each shot not yet grouped seeds a group of the look-alikes that follow it.
        // Shots that don't match stay free to seed or join a later group.
        let rest = eligible.filter { !grouped.contains($0.id) }
        var taken = [Bool](repeating: false, count: rest.count)
        for i in rest.indices where !taken[i] {
            let seed = rest[i]
            guard let seedPrint = prints[seed.id] else { continue }
            var members = [i]
            var last = seed.features.createdAt
            var misses: [NearMiss] = []
            for j in rest.indices.dropFirst(i + 1) where !taken[j] {
                let time = rest[j].features.createdAt
                let gap = time.timeIntervalSince(last)
                guard gap <= tunables.maxGap, time.timeIntervalSince(seed.features.createdAt) <= tunables.maxSpan,
                      members.count < tunables.sizes.upperBound else { break }
                guard let print = prints[rest[j].id] else { continue }
                let d = distance(seedPrint, print)
                if d <= tunables.maxDistance {
                    members.append(j)
                    last = time
                } else if d <= tunables.maxDistance + tunables.nearMissMargin {
                    misses.append(NearMiss(seed: seed.id, other: rest[j].id, distance: d, gap: gap))
                }
            }
            result.nearMisses += misses
            guard members.count >= tunables.sizes.lowerBound else { continue }
            for member in members { taken[member] = true }
            result.groups.append(makeGroup(members.map { rest[$0] }, prints: prints, isBurst: false))
        }

        // Oldest group first, as the shots were taken.
        let position = Dictionary(uniqueKeysWithValues: eligible.enumerated().map { ($1.id, $0) })
        result.groups.sort { position[$0.ids[0], default: 0] < position[$1.ids[0], default: 0] }
        return result
    }

    /// The candidates `neighborIDs` returns, split into sets `group` handles independently, each oldest
    /// first. No group spans a wait longer than `maxGap` between consecutive eligible shots (a seed's
    /// look-alikes must follow within `maxGap` of the last one taken), and a burst's frames always land
    /// in one set. So grouping each set on its own and `merge`-ing the results gives exactly what
    /// grouping them all at once does.
    func components(_ candidates: [RankCandidate]) -> [[RankCandidate]] {
        let eligible = sorted(candidates.filter { Self.isEligible($0.features) })
        let neighbors = neighborIDs(candidates)
        var parent = Array(eligible.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func join(_ a: Int, _ b: Int) {
            let ra = root(a), rb = root(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for i in eligible.indices.dropFirst()
        where eligible[i].features.createdAt.timeIntervalSince(eligible[i - 1].features.createdAt) <= tunables.maxGap {
            join(i - 1, i)
        }
        var firstFrame: [String: Int] = [:]
        for (i, candidate) in eligible.enumerated() {
            guard let burst = candidate.features.burstID else { continue }
            if let first = firstFrame[burst] { join(first, i) } else { firstFrame[burst] = i }
        }
        var sets: [Int: [RankCandidate]] = [:]
        for (i, candidate) in eligible.enumerated() where neighbors.contains(candidate.id) {
            sets[root(i), default: []].append(candidate)
        }
        return sets.sorted { $0.key < $1.key }.map(\.value)
    }

    /// `group` results for separate `components` of `candidates`, as one `group` call on all of them
    /// would return them: oldest group first.
    func merge(_ results: [Result], of candidates: [RankCandidate]) -> Result {
        let position = Dictionary(uniqueKeysWithValues: sorted(candidates).enumerated().map { ($1.id, $0) })
        var merged = Result()
        for result in results {
            merged.groups += result.groups
            merged.nearMisses += result.nearMisses
        }
        merged.groups.sort { position[$0.ids[0], default: 0] < position[$1.ids[0], default: 0] }
        return merged
    }

    // MARK: Internals

    private func sorted(_ candidates: [RankCandidate]) -> [RankCandidate] {
        candidates.sorted(by: RankCandidate.oldestFirst)
    }

    private func makeGroup(_ members: [RankCandidate], prints: [LibraryItem.ID: FeaturePrint], isBurst: Bool) -> Group {
        var widest: Float = 0
        for (i, a) in members.enumerated() {
            for b in members.dropFirst(i + 1) {
                if let pa = prints[a.id], let pb = prints[b.id] { widest = max(widest, distance(pa, pb)) }
            }
        }
        let first = members.first?.features.createdAt ?? .distantPast
        let last = members.last?.features.createdAt ?? first
        return Group(ids: members.map(\.id), maxDistance: widest, span: last.timeIntervalSince(first), isBurst: isBurst)
    }
}
