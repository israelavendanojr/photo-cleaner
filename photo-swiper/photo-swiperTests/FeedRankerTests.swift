import Foundation
import Testing
@testable import photo_swiper

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func features(
    mb: Double = 2,
    videoSeconds: TimeInterval? = nil,
    screenshot: Bool = false,
    daysOld: Double = 1,
    inBurst: Bool = false,
    burstPick: Bool = false,
    edited: Bool = false,
    favorite: Bool = false
) -> AssetFeatures {
    AssetFeatures(
        createdAt: now.addingTimeInterval(-daysOld * 86_400),
        bytes: Int64(mb * 1_000_000),
        isVideo: videoSeconds != nil,
        duration: videoSeconds ?? 0,
        isScreenshot: screenshot,
        isFavorite: favorite,
        isInBurst: inBurst,
        isBurstPick: burstPick,
        hasAdjustments: edited
    )
}

struct FeedRankerTests {
    private let ranker = FeedRanker()

    private func score(_ features: AssetFeatures) -> Double {
        ranker.score(features, now: now).total
    }

    @Test func bigVideoBeatsPhoto() {
        #expect(score(features(mb: 2000, videoSeconds: 120)) > score(features(mb: 2)))
    }

    @Test func biggerFileRanksHigher() {
        #expect(score(features(mb: 40)) > score(features(mb: 4)))
    }

    @Test func editedPhotoSinks() {
        #expect(score(features(edited: true)) < score(features()))
    }

    @Test func favoriteSinks() {
        #expect(score(features(favorite: true)) < score(features()))
    }

    @Test func oldScreenshotOutranksFreshOne() {
        #expect(score(features(mb: 0.5, screenshot: true, daysOld: 90)) > score(features(mb: 0.5, screenshot: true, daysOld: 1)))
    }

    @Test func freshScreenshotOutranksOrdinaryPhoto() {
        #expect(score(features(mb: 0.5, screenshot: true)) > score(features(mb: 3)))
    }

    @Test func screenshotAgeBoostIsCapped() {
        let shot = { (days: Double) in ranker.score(features(screenshot: true, daysOld: days), now: now) }
        let partValue = { (breakdown: FeedRanker.Breakdown) in breakdown.parts.first { $0.name == "shot age" }?.value }
        #expect(partValue(shot(200)) == partValue(shot(400)))
    }

    @Test func extraBurstFrameOutranksBurstPick() {
        #expect(score(features(inBurst: true)) > score(features(inBurst: true, burstPick: true)))
    }

    @Test func futureDatesDontScoreNegativeAge() {
        let breakdown = ranker.score(features(daysOld: -30), now: now)
        #expect(!breakdown.parts.contains { $0.name == "age" })
    }

    @Test func partsSumToTotal() {
        let breakdown = ranker.score(features(mb: 300, videoSeconds: 90, daysOld: 800, edited: true), now: now)
        #expect(abs(breakdown.parts.map(\.value).reduce(0, +) - breakdown.total) < 1e-9)
        #expect(Set(breakdown.parts.map(\.name)) == ["size", "video", "age", "edited"])
    }
}

struct FeedRankerImageSignalTests {
    private let ranker = FeedRanker()
    private static let legacyParts: Set<String> = ["size", "video", "screenshot", "shot age", "age", "burst", "edited", "favorite"]

    private func analyzed(
        sharpness: Double = 500, dark: Double = 0.05, aesthetic: Double = 0, utility: Bool = false
    ) -> AssetFeatures {
        var f = features()
        f.sharpness = sharpness
        f.exposure = ExposureStats(mean: 0.5, darkFraction: dark, brightFraction: 0.05)
        f.aesthetic = aesthetic
        f.isUtility = utility
        return f
    }

    private func part(_ name: String, of features: AssetFeatures) -> Double? {
        ranker.score(features, now: now).parts.first { $0.name == name }?.value
    }

    @Test func unanalyzedFeaturesScoreExactlyAsBefore() {
        let samples = [
            features(), features(mb: 300, videoSeconds: 90, daysOld: 800, edited: true),
            features(mb: 0.5, screenshot: true, daysOld: 45), features(inBurst: true, favorite: true),
        ]
        for sample in samples {
            let breakdown = ranker.score(sample, now: now)
            #expect(Set(breakdown.parts.map(\.name)).isSubset(of: Self.legacyParts))
        }
        // Pinned from the metadata-only ranker: size log10(2) plus one day of age.
        let plain = ranker.score(features(), now: now)
        #expect(abs(plain.total - (log10(2.0) + 0.1 / 365)) < 1e-9)
    }

    @Test func aGoodAnalyzedPhotoAddsNoParts() {
        #expect(ranker.score(analyzed(), now: now) == ranker.score(features(), now: now))
    }

    @Test func accidentalRanksHighest() {
        #expect(part("accidental", of: analyzed(sharpness: 1, dark: 1)) == FeedRanker.Weights().accidental)
        #expect(part("blurry", of: analyzed(sharpness: 1, dark: 1)) == nil, "Accidental replaces blurry")
        #expect(ranker.score(analyzed(sharpness: 1, dark: 1), now: now).total > ranker.score(analyzed(sharpness: 5), now: now).total)
    }

    @Test func blurryRanksHigher() {
        #expect(part("blurry", of: analyzed(sharpness: 5)) == FeedRanker.Weights().blurry)
        #expect(ranker.score(analyzed(sharpness: 5), now: now).total > ranker.score(analyzed(), now: now).total)
    }

    @Test func utilityRanksHigher() {
        #expect(part("utility", of: analyzed(utility: true)) == FeedRanker.Weights().utility)
    }

    @Test func lowAestheticRisesAndHighAestheticSinks() {
        #expect(part("low aesthetic", of: analyzed(aesthetic: -1)) == FeedRanker.Weights().lowAesthetic)
        #expect(part("low aesthetic", of: analyzed(aesthetic: -0.5)) == FeedRanker.Weights().lowAesthetic / 2)
        #expect(part("high aesthetic", of: analyzed(aesthetic: 0.5)) == nil)
        #expect(part("high aesthetic", of: analyzed(aesthetic: 1)) == FeedRanker.Weights().highAesthetic)
        #expect(ranker.score(analyzed(aesthetic: 0.9), now: now).total < ranker.score(analyzed(aesthetic: 0.2), now: now).total)
    }
}

struct SessionPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func planner(limit: Int = 20, maxBatch: Int = 40) -> SessionPlanner {
        SessionPlanner(limit: limit, minBatch: 3, maxBatch: maxBatch, calendar: calendar)
    }

    private func photo(_ id: String, mb: Double = 2) -> RankCandidate {
        RankCandidate(id: id, features: features(mb: mb))
    }

    /// Screenshots a few hours apart, all in the same calendar week as `now`.
    private func shots(_ count: Int, prefix: String = "s") -> [RankCandidate] {
        (0..<count).map { i in
            RankCandidate(id: "\(prefix)\(i)", features: features(mb: 0.5, screenshot: true, daysOld: Double(i) / 24))
        }
    }

    @Test func bestItemComesFirst() {
        let pool = [photo("a"), photo("b"), RankCandidate(id: "v", features: features(mb: 500, videoSeconds: 60))]
        #expect(planner().plan(pool, now: now).first == .single("v"))
    }

    @Test func limitCountsEveryItem() {
        let pool = (0..<10).map { photo("p\($0)", mb: Double(10 - $0)) }
        #expect(planner(limit: 3).plan(pool, now: now) == [.single("p0"), .single("p1"), .single("p2")])
    }

    @Test func screenshotsFromOneWeekBecomeOneBatch() {
        let plan = planner().plan(shots(3) + [photo("a")], now: now)
        #expect(plan.count == 2)
        guard case .screenshots(_, let ids) = plan.first else {
            Issue.record("Expected a screenshot batch first, got \(plan)")
            return
        }
        #expect(Set(ids) == ["s0", "s1", "s2"])
    }

    @Test func smallWeeksBecomeSingleCards() {
        let plan = planner().plan(shots(2), now: now)
        #expect(Set(plan) == [.single("s0"), .single("s1")])
    }

    @Test func overflowScreenshotsWaitForLaterSession() {
        let plan = planner(maxBatch: 4).plan(shots(6) + [photo("a")], now: now)
        #expect(plan.flatMap(\.ids).count == 5)
        #expect(plan.contains(.single("a")))
    }

    @Test func emptyPoolMakesEmptyPlan() {
        #expect(planner().plan([], now: now).isEmpty)
    }
}
