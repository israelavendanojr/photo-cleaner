import Foundation
import Testing
@testable import photo_swiper

/// Prints are 2-D points, so distances are easy to read: (0, 0) to (0.3, 0) is 0.3.
struct SimilarGrouperTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let grouper = SimilarGrouper()

    private func shot(
        _ id: String, at seconds: TimeInterval, burst: String? = nil,
        video: Bool = false, screenshot: Bool = false, utility: Bool? = false
    ) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(
            createdAt: base.addingTimeInterval(seconds), bytes: 3_000_000, isVideo: video, isScreenshot: screenshot,
            burstID: burst, isUtility: utility
        ))
    }

    private func point(_ x: Float, _ y: Float = 0) -> FeaturePrint {
        FeaturePrint(vector: [x, y])
    }

    private func groups(_ shots: [RankCandidate], _ prints: [String: FeaturePrint]) -> [[String]] {
        grouper.group(shots, prints: prints).groups.map(\.ids)
    }

    @Test func burstFramesGroupWhateverTheyLookLike() {
        let shots = [shot("a", at: 0, burst: "b1"), shot("b", at: 1, burst: "b1"), shot("c", at: 2, burst: "b1"), shot("d", at: 3)]
        let result = grouper.group(shots, prints: ["a": point(0), "b": point(5), "c": point(10), "d": point(20)])
        #expect(result.groups.map(\.ids) == [["a", "b", "c"]])
        #expect(result.groups[0].isBurst)
        #expect(result.groups[0].maxDistance == 10)
    }

    @Test func aLongBurstSplitsIntoEvenRuns() {
        let shots = (0..<20).map { shot("f\($0)", at: Double($0) / 10, burst: "b1") }
        let prints = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, point(0)) })
        #expect(groups(shots, prints).map(\.count) == [7, 7, 6])
        #expect(Set(groups(shots, prints).flatMap { $0 }).count == 20)
    }

    @Test func aGapLongerThanMaxGapEndsTheGroup() {
        let shots = [shot("a", at: 0), shot("b", at: 60), shot("c", at: 200)]
        #expect(groups(shots, ["a": point(0), "b": point(0), "c": point(0)]) == [["a", "b"]])
    }

    @Test func shotsChainWithinTheGapUpToMaxSpan() {
        let shots = [shot("a", at: 0), shot("b", at: 80), shot("c", at: 160), shot("d", at: 240), shot("e", at: 320)]
        let prints = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, point(0)) })
        #expect(groups(shots, prints) == [["a", "b", "c", "d"]], "e is within the gap of d but 320 s from the seed")
    }

    @Test func membersMustBeCloseToTheSeedNotJustTheLastShot() {
        // Each step is 0.3, under the 0.45 threshold, but c is 0.6 from the seed.
        let shots = [shot("a", at: 0), shot("b", at: 5), shot("c", at: 10)]
        #expect(groups(shots, ["a": point(0), "b": point(0.3), "c": point(0.6)]) == [["a", "b"]])
    }

    @Test func groupsStopAtEightAndTheRestStartAnother() {
        let shots = (0..<10).map { shot("s\($0)", at: Double($0)) }
        let prints = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, point(0)) })
        #expect(groups(shots, prints).map(\.count) == [8, 2])
    }

    @Test func interleavedScenesEachGetTheirOwnGroup() {
        let shots = [shot("a1", at: 0), shot("b1", at: 5), shot("a2", at: 10), shot("b2", at: 15)]
        let prints = ["a1": point(0), "a2": point(0.1), "b1": point(5), "b2": point(5.1)]
        #expect(groups(shots, prints) == [["a1", "a2"], ["b1", "b2"]])
    }

    @Test func onlyPhotosWithPrintsAreGrouped() {
        let shots = [
            shot("photo", at: 0), shot("video", at: 1, video: true), shot("screenshot", at: 2, screenshot: true),
            shot("receipt", at: 3, utility: true), shot("unindexed", at: 4),
            shot("burstVideo", at: 5, burst: "b1", video: true), shot("burstPhoto", at: 6, burst: "b1"),
        ]
        var prints = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, point(0)) })
        prints["unindexed"] = nil
        // The burst has one eligible frame left, so it falls through and groups with the other photo by time and looks.
        #expect(groups(shots, prints) == [["photo", "burstPhoto"]])
    }

    @Test func unknownUtilityStillGroups() {
        let shots = [shot("a", at: 0, utility: nil), shot("b", at: 1, utility: nil)]
        #expect(groups(shots, ["a": point(0), "b": point(0)]) == [["a", "b"]])
    }

    @Test func nearMissesAreJustPastTheThreshold() {
        let shots = [shot("a", at: 0), shot("near", at: 10), shot("far", at: 20)]
        let result = grouper.group(shots, prints: ["a": point(0), "near": point(0.5), "far": point(0, 0.7)])
        #expect(result.groups.isEmpty)
        #expect(result.nearMisses.map(\.other) == ["near"])
        #expect(result.nearMisses.first?.seed == "a")
        #expect(result.nearMisses.first?.gap == 10)
    }

    @Test func theDistanceIsInjectable() {
        var alwaysClose = SimilarGrouper()
        alwaysClose.distance = { _, _ in 0 }
        let shots = [shot("a", at: 0), shot("b", at: 1)]
        #expect(alwaysClose.group(shots, prints: ["a": point(0), "b": point(100)]).groups.map(\.ids) == [["a", "b"]])
    }

    @Test func inputOrderDoesNotMatter() {
        let shots = (0..<6).map { shot("s\($0)", at: Double($0 * 20)) }
        let prints = Dictionary(uniqueKeysWithValues: shots.enumerated().map { ($1.id, point($0 < 3 ? 0 : 3)) })
        #expect(groups(shots.reversed(), prints) == groups(shots, prints))
        #expect(groups(shots, prints) == [["s0", "s1", "s2"], ["s3", "s4", "s5"]])
    }

    @Test func neighborIDsAreTheShotsThatCouldGroup() {
        let shots = [
            shot("alone", at: 0), shot("a", at: 1_000), shot("b", at: 1_060), shot("video", at: 1_070, video: true),
            shot("burst1", at: 5_000, burst: "b1"), shot("burst2", at: 9_000, burst: "b1"),
        ]
        #expect(grouper.neighborIDs(shots) == ["a", "b", "burst1", "burst2"])
    }

    /// Saved marks are keyed by group id, so the same members must always get the same id.
    @Test func similarCardIDsDependOnlyOnTheMembers() {
        let id = PhotoKitFeedBuilder.similarID(["B/L0/001", "A/L0/001", "C/L0/001"])
        #expect(id == PhotoKitFeedBuilder.similarID(["A/L0/001", "B/L0/001", "C/L0/001"]))
        #expect(id != PhotoKitFeedBuilder.similarID(["A/L0/001", "B/L0/001"]))
        #expect(id.hasPrefix("similar-") && id.count == "similar-".count + 16)
    }
}
