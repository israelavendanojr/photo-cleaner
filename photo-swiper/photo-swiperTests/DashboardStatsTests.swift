import Foundation
import Testing
@testable import photo_swiper

/// The dashboard's numbers, from made-up history and features. Fixed time and calendar throughout.
struct DashboardStatsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 12 Nov 2025, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_762_948_800)
    private let day: TimeInterval = 86_400

    private func entry(_ daysAgo: Double, _ bytes: Int64, _ category: CleanupCategory = .photo) -> CleanupEntry {
        CleanupEntry(at: now.addingTimeInterval(-daysAgo * day), category: category, count: 1, bytes: bytes)
    }

    private func make(_ history: [CleanupEntry], scan: LibraryScan? = nil, reviewed: Double = 0) -> DashboardSnapshot {
        DashboardStats.make(history: history, scan: scan, reviewedFraction: reviewed, now: now, calendar: Self.calendar)
    }

    @Test func nothingClearedIsAllZero() {
        let snapshot = make([])
        #expect(snapshot.totalCleared == 0)
        #expect(snapshot.cumulative.isEmpty)
        #expect(snapshot.weekly.isEmpty)
        #expect(snapshot.opportunities.isEmpty)
        #expect(snapshot.health == nil)
        #expect(snapshot.computedAt == now)
    }

    @Test func weekOverWeekIsTheLastSevenDaysAgainstTheSevenBefore() {
        let snapshot = make([entry(0.5, 100), entry(6.9, 20), entry(7.1, 5), entry(13.9, 1), entry(15, 1_000)])
        #expect(snapshot.totalCleared == 1_126)
        #expect(snapshot.clearedThisWeek == 120)
        #expect(snapshot.clearedLastWeek == 6)
    }

    @Test func theRunningTotalStartsAtZeroRisesAndReachesToday() throws {
        let snapshot = make([entry(10, 300), entry(10, 200), entry(3, 50)])
        let totals = snapshot.cumulative.map(\.total)
        #expect(totals == [0, 500, 550, 550])
        #expect(zip(totals, totals.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(snapshot.cumulative.last?.date == Self.calendar.startOfDay(for: now))
        #expect(snapshot.cumulative.last?.total == snapshot.totalCleared)
    }

    @Test func weeksRunFromTheFirstCleanupToThisWeekWithEmptyWeeksIncluded() throws {
        let snapshot = make([entry(16, 300), entry(1, 40)])
        #expect(snapshot.weekly.map(\.bytes) == [300, 0, 40])
        let starts = snapshot.weekly.map(\.date)
        #expect(starts.allSatisfy { Self.calendar.component(.weekday, from: $0) == 2 }, "Weeks start on the calendar's first weekday")
        #expect(snapshot.weekly.reduce(0) { $0 + $1.bytes } == snapshot.totalCleared)
    }

    @Test func weeksAreCapped() {
        let snapshot = make([entry(400, 1), entry(0, 1)])
        #expect(snapshot.weekly.count == DashboardStats.maxWeeks)
        #expect(snapshot.weekly.last?.bytes == 1)
    }

    @Test func opportunitiesAreBiggestFirstAndTiesKeepCategoryOrder() {
        let scan = LibraryScan(buckets: [
            .screenshot: .init(count: 9, bytes: 500),
            .video: .init(count: 1, bytes: 900),
            .duplicate: .init(count: 2, bytes: 500),
            .burst: .init(count: 0, bytes: 0),
        ], indexedCount: 20, indexedBytes: 10_000)
        let snapshot = make([], scan: scan)
        #expect(snapshot.opportunities.map(\.category) == [.video, .duplicate, .screenshot])
        #expect(snapshot.recoverableBytes == 1_900)
    }

    @Test(arguments: [(Int64(0), 1.0, 1.0), (10_000, 0.0, 0.0), (5_000, 0.5, 0.5), (20_000, 1.0, 0.5)])
    func healthWeighsClutterAndReviewEqually(recoverable: Int64, reviewed: Double, expected: Double) throws {
        let health = try #require(DashboardStats.health(recoverable: recoverable, of: 10_000, reviewedFraction: reviewed))
        #expect(abs(health - expected) < 0.000_1)
        #expect((0...1).contains(health))
    }

    @Test func noHealthUntilSomethingIsAnalyzed() {
        #expect(DashboardStats.health(recoverable: 0, of: 0, reviewedFraction: 0.5) == nil)
    }
}

/// What's left to clear, sorted from cached features and groups.
struct LibraryScanTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func features(bytes: Int64, video: Bool = false, screenshot: Bool = false, burst: Bool = false,
                          pick: Bool = false, favorite: Bool = false) -> AssetFeatures {
        AssetFeatures(createdAt: date, bytes: bytes, isVideo: video, isScreenshot: screenshot, isFavorite: favorite,
                      isInBurst: burst, isBurstPick: pick)
    }

    @Test func eachItemCountsOnceInTheFirstBucketItFits() {
        let library: [LibraryItem.ID: AssetFeatures] = [
            "big-video": features(bytes: 80_000_000, video: true),
            "small-video": features(bytes: 2_000_000, video: true),
            "shot": features(bytes: 1_000, screenshot: true),
            "burst": features(bytes: 3_000, burst: true),
            "burst-pick": features(bytes: 3_000, burst: true, pick: true),
            "similar-best": features(bytes: 4_000, burst: true),
            "similar-other": features(bytes: 4_000, burst: true),
            "copy": features(bytes: 5_000),
            "original": features(bytes: 5_000),
            "favorite-shot": features(bytes: 1_000, screenshot: true, favorite: true),
            "decided": features(bytes: 9_000, screenshot: true),
        ]
        let scan = LibraryScan.make(
            features: library, excluding: ["decided"],
            duplicates: [PlannedGroup(ids: ["original", "copy"], bestID: "original", reason: "")],
            similar: [PlannedGroup(ids: ["similar-best", "similar-other"], bestID: "similar-best", reason: "")],
            scanPercent: 40
        )

        #expect(scan.buckets[.video] == .init(count: 1, bytes: 80_000_000))
        #expect(scan.buckets[.screenshot] == .init(count: 1, bytes: 1_000), "Favorites and decided items don't count")
        #expect(scan.buckets[.burst] == .init(count: 2, bytes: 7_000), "The best of a similar set is still a burst shot")
        #expect(scan.buckets[.similar] == .init(count: 1, bytes: 4_000), "Only the shots other than the best")
        #expect(scan.buckets[.duplicate] == .init(count: 1, bytes: 5_000), "Only the extra copies")
        #expect(scan.indexedCount == library.count - 1)
        #expect(scan.scanPercent == 40)
    }
}

/// The dashboard's cache and refresh.
@MainActor
struct DashboardControllerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "dashboard-\(UUID().uuidString).json")
    }

    @Test func aRefreshComputesAndTheNextLaunchStartsFromTheCache() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = InMemoryProgressStore()
        store.recordCleanup([CleanupEntry(at: now, category: .video, count: 1, bytes: 900)])
        let controller = DashboardController(builder: MockFeedBuilder(), store: store, cacheURL: url, now: { now })
        #expect(controller.snapshot == nil)
        #expect(controller.isStale)

        await controller.refresh(reviewedFraction: 0.25)

        let snapshot = try #require(controller.snapshot)
        #expect(snapshot.totalCleared == 900)
        #expect(snapshot.opportunities.first?.category == .video)
        #expect(!controller.isStale)
        #expect(!controller.isRefreshing)

        let relaunched = DashboardController(builder: MockFeedBuilder(), store: InMemoryProgressStore(), cacheURL: url, now: { now })
        #expect(relaunched.snapshot == snapshot, "Shown at once, before any refresh")
    }

    @Test func itGoesStaleAfterAWhile() async {
        var clock = now
        let controller = DashboardController(builder: MockFeedBuilder(), store: InMemoryProgressStore(), cacheURL: nil, now: { clock })
        await controller.refresh(reviewedFraction: 0)
        #expect(!controller.isStale)
        clock = now.addingTimeInterval(DashboardController.staleAfter + 1)
        #expect(controller.isStale)
    }

    @Test func clearingForgetsTheCache() async {
        let url = cacheURL()
        let controller = DashboardController(builder: MockFeedBuilder(), store: InMemoryProgressStore(), cacheURL: url, now: { now })
        await controller.refresh(reviewedFraction: 0)
        controller.clear()
        #expect(controller.snapshot == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }
}
