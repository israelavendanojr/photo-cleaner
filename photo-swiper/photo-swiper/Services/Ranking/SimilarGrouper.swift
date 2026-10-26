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
    var distance: @Sendable (FeaturePrint, FeaturePrint) -> Float = FeaturePrint.euclidean

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
            for chunk in balancedChunks(sorted(frames)) {
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

    // MARK: Internals

    /// Oldest first; ties by id so the result doesn't depend on input order.
    private func sorted(_ candidates: [RankCandidate]) -> [RankCandidate] {
        candidates.sorted { a, b in
            a.features.createdAt != b.features.createdAt ? a.features.createdAt < b.features.createdAt : a.id < b.id
        }
    }

    /// A burst over the size limit, cut into consecutive runs of near-equal length.
    private func balancedChunks(_ frames: [RankCandidate]) -> [[RankCandidate]] {
        let max = tunables.sizes.upperBound
        let count = (frames.count + max - 1) / max
        var chunks: [[RankCandidate]] = []
        var start = 0
        for k in 0..<count {
            let size = frames.count / count + (k < frames.count % count ? 1 : 0)
            chunks.append(Array(frames[start..<start + size]))
            start += size
        }
        return chunks
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
