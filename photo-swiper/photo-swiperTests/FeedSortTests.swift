import Foundation
import Testing
@testable import photo_swiper

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// `SessionPlanner` and `FeedSort` under each sort (JUN-125), with made-up features.
struct FeedSortTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func planner(limit: Int = 20) -> SessionPlanner {
        SessionPlanner(limit: limit, minBatch: 3, maxBatch: 40, calendar: calendar)
    }

    private func item(_ id: String, mb: Double = 2, daysOld: Double = 1, date: Date? = nil, screenshot: Bool = false) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(createdAt: date ?? now.addingTimeInterval(-daysOld * 86_400),
                                                      bytes: Int64(mb * 1_000_000), isScreenshot: screenshot))
    }

    private func group(_ ids: [String]) -> PlannedGroup {
        PlannedGroup(ids: ids, bestID: ids[0], reason: "Sharpest of the set")
    }

    // MARK: Order

    @Test func largestPutsTheBiggestFirst() {
        let pool = [item("a", mb: 5), item("b", mb: 900), item("c", mb: 40)]
        #expect(planner().plan(pool, sort: .largest, now: now) == [.single("b"), .single("c"), .single("a")])
    }

    @Test func largestBreaksTiesNewerFirstThenByID() {
        let pool = [item("old", mb: 5, daysOld: 10), item("new", mb: 5, daysOld: 1), item("b", mb: 5, daysOld: 1)]
        #expect(planner().plan(pool, sort: .largest, now: now) == [.single("b"), .single("new"), .single("old")])
    }

    @Test func newestAndOldestOrderByDateTakenWithTiesByID() {
        let pool = [item("mid", daysOld: 5), item("b", daysOld: 1), item("a", daysOld: 1), item("old", daysOld: 300)]
        #expect(planner().plan(pool, sort: .newest, now: now) == [.single("a"), .single("b"), .single("mid"), .single("old")])
        #expect(planner().plan(pool, sort: .oldest, now: now) == [.single("old"), .single("mid"), .single("a"), .single("b")])
    }

    @Test func aSortIgnoresTheRankerScore() {
        // A huge video would rank first under Recommended.
        let video = RankCandidate(id: "v", features: AssetFeatures(createdAt: now.addingTimeInterval(-86_400 * 30),
                                                                   bytes: 900_000_000, isVideo: true, duration: 120))
        let pool = [video, item("new", daysOld: 0.1)]
        #expect(planner().plan(pool, now: now).first == .single("v"))
        #expect(planner().plan(pool, sort: .newest, now: now).first == .single("new"))
    }

    @Test func undatedItemsShowOnlyUnderRecommendedAndLargest() {
        let pool = [item("dated", mb: 1), item("undated", mb: 50, date: .distantPast)]
        #expect(!planner().plan(pool, sort: .newest, now: now).flatMap(\.ids).contains("undated"))
        #expect(!planner().plan(pool, sort: .oldest, now: now).flatMap(\.ids).contains("undated"))
        #expect(planner().plan(pool, sort: .largest, now: now).first == .single("undated"))
        #expect(planner().plan(pool, now: now).flatMap(\.ids).contains("undated"))
    }

    // MARK: Bundles

    @Test func largestPlacesAGroupByAllItsMembersBytes() {
        // 3 × 30 MB = 90 MB together: ahead of a 60 MB single, behind a 100 MB one.
        let similar = group(["g1", "g2", "g3"])
        let pool = [item("g1", mb: 30), item("g2", mb: 30), item("g3", mb: 30), item("big", mb: 100), item("mid", mb: 60)]
        let plan = planner().plan(pool, groups: [similar], sort: .largest, now: now)
        #expect(plan.map(\.ids) == [["big"], ["g1", "g2", "g3"], ["mid"]])
    }

    @Test func datesPlaceAGroupByItsOldestOrNewestMember() {
        let copies = group(["d1", "d2"])
        let pool = [item("d1", daysOld: 2), item("d2", daysOld: 50), item("x", daysOld: 10)]
        // Newest member is 2 days old: ahead of x. Oldest member is 50 days old: ahead of x too.
        #expect(planner().plan(pool, duplicates: [copies], sort: .newest, now: now).first?.ids == ["d1", "d2"])
        #expect(planner().plan(pool, duplicates: [copies], sort: .oldest, now: now).first?.ids == ["d1", "d2"])
        let between = [item("d1", daysOld: 2), item("d2", daysOld: 50), item("x", daysOld: 1), item("y", daysOld: 100)]
        #expect(planner().plan(between, duplicates: [copies], sort: .newest, now: now).map(\.ids) == [["x"], ["d1", "d2"], ["y"]])
        #expect(planner().plan(between, duplicates: [copies], sort: .oldest, now: now).map(\.ids) == [["y"], ["d1", "d2"], ["x"]])
    }

    @Test func aGroupedPhotoNeverShowsAsASingleUnderASort() {
        let similar = group(["g1", "g2"])
        let pool = [item("g1", mb: 500), item("g2", mb: 1), item("a", mb: 10)]
        let plan = planner().plan(pool, groups: [similar], sort: .largest, now: now)
        #expect(!plan.contains(.single("g1")) && !plan.contains(.single("g2")))
    }

    @Test func aScreenshotBatchGoesWhereItsFirstMemberLands() {
        let shots = (0..<3).map { item("s\($0)", mb: 0.5, daysOld: 0.5 + Double($0) / 24, screenshot: true) }
        let pool = shots + [item("newer", daysOld: 0.1), item("older", daysOld: 40)]
        let plan = planner().plan(pool, sort: .newest, now: now)
        #expect(plan.count == 3)
        #expect(plan.first == .single("newer"))
        guard case .screenshots(_, let ids) = plan[1] else {
            Issue.record("Expected the batch second, got \(plan)")
            return
        }
        #expect(ids == ["s0", "s1", "s2"])
        #expect(plan.last == .single("older"))
    }

    @Test func aSortDoesNotRearrangeSimilarCards() {
        // Two big groups rank next to each other. Recommended pulls a single between them; a sort leaves them.
        let groups = [group(["a1", "a2"]), group(["b1", "b2"])]
        let pool = ["a1", "a2", "b1", "b2"].map { item($0, mb: 300) } + [item("p", mb: 1)]
        let recommended = planner().plan(pool, groups: groups, now: now)
        #expect(!zip(recommended, recommended.dropFirst()).contains { $0.isSimilar && $1.isSimilar })
        let sorted = planner().plan(pool, groups: groups, sort: .largest, now: now)
        #expect(sorted.map(\.ids) == [["a1", "a2"], ["b1", "b2"], ["p"]])
    }

    // MARK: Cards

    @Test func cardsOrderTheSameWayForTheMockBuilder() {
        func photo(_ id: String, mb: Int64, daysOld: Double) -> FeedCard {
            .photo(LibraryItem(id: id, kind: .photo, date: now.addingTimeInterval(-daysOld * 86_400), location: nil,
                               bytes: mb * 1_000_000, image: .bundled("photo-sunset")))
        }
        let cards = [photo("a", mb: 1, daysOld: 3), photo("b", mb: 9, daysOld: 9), photo("c", mb: 5, daysOld: 1)]
        #expect(FeedSort.recommended.ordered(cards) == cards)
        #expect(FeedSort.largest.ordered(cards).map(\.id) == ["item-b", "item-c", "item-a"])
        #expect(FeedSort.newest.ordered(cards).map(\.id) == ["item-c", "item-a", "item-b"])
        #expect(FeedSort.oldest.ordered(cards).map(\.id) == ["item-b", "item-a", "item-c"])
    }
}
