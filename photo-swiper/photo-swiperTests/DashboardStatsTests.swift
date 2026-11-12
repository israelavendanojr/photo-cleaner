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

/// The library profile's sections: timeline, forecast, composition, activity and insights.
struct DashboardInsightsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 12 Nov 2025, noon UTC. This week starts Monday 10 Nov.
    private let now = Date(timeIntervalSince1970: 1_762_948_800)
    private let day: TimeInterval = 86_400

    private func cleanup(_ daysAgo: Double, _ bytes: Int64 = 100) -> CleanupEntry {
        CleanupEntry(at: now.addingTimeInterval(-daysAgo * day), category: .photo, count: 1, bytes: bytes)
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private func profile(_ monthly: [Date: LibraryScan.Bucket], recent: Int64 = 0, oldest: Date? = nil) -> LibraryProfile {
        let all = LibraryScan.Bucket(count: monthly.values.reduce(0) { $0 + $1.count }, bytes: monthly.values.reduce(0) { $0 + $1.bytes })
        return LibraryProfile(composition: [.photo: all], monthly: monthly, addedRecently: recent, oldestUnreviewed: oldest)
    }

    private func make(history: [CleanupEntry] = [], profile: LibraryProfile? = nil, storage: DeviceStorage? = nil) -> DashboardSnapshot {
        DashboardStats.make(history: history, scan: LibraryScan(profile: profile), reviewedFraction: 0, storage: storage,
                            now: now, calendar: Self.calendar)
    }

    // MARK: Activity

    @Test func theHeatmapRunsSixteenWholeWeeksToToday() throws {
        let activity = try #require(make().activity)
        #expect(activity.days.count == 15 * 7 + 3, "Fifteen whole weeks, then Monday to Wednesday")
        #expect(Self.calendar.component(.weekday, from: try #require(activity.days.first).date) == 2)
        #expect(activity.days.last?.date == Self.calendar.startOfDay(for: now))
        #expect(activity.days.allSatisfy { $0.level == 0 })
        #expect(activity.streakWeeks == 0)
    }

    @Test func levelsAreQuartilesOfTheDaysWithCleanups() throws {
        let activity = try #require(make(history: [cleanup(1, 10), cleanup(2, 20), cleanup(3, 30), cleanup(4, 40)]).activity)
        let levels = Dictionary(activity.days.map { ($0.bytes, $0.level) }, uniquingKeysWith: { first, _ in first })
        #expect(levels[10] == 1 && levels[20] == 2 && levels[30] == 3 && levels[40] == 4)
        #expect(levels[0] == 0)
        #expect(activity.activeDays == 4)
    }

    @Test(arguments: [
        ([Double](), 0),
        ([0.0, 7, 14], 3), // this week and the two before
        ([7.0, 14], 2), // none yet this week: last week's run still counts
        ([0.0, 14], 1), // a missed week breaks it
        ([0.0, 0.5, 1], 1), // several days in one week count once
    ])
    func theStreakCountsWeeksInARow(daysAgo: [Double], weeks: Int) throws {
        let activity = try #require(make(history: daysAgo.map { cleanup($0) }).activity)
        #expect(activity.streakWeeks == weeks)
    }

    // MARK: Library

    @Test func theForecastDividesWhatsFreeByTheRecentPace() throws {
        let storage = DeviceStorage(total: 10_000, available: 900)
        let paced = try #require(make(profile: profile([month(2025, 11): .init(count: 1, bytes: 900)], recent: 900), storage: storage).forecast)
        #expect(paced.bytesPerDay == 10)
        #expect(paced.daysUntilFull == 90)
        #expect(paced.libraryBytes == 900)

        let still = try #require(make(profile: profile([month(2025, 1): .init(count: 1, bytes: 5)]), storage: storage).forecast)
        #expect(still.daysUntilFull == nil, "Nothing new lately: no date")
        #expect(make(profile: profile([month(2025, 1): .init(count: 1, bytes: 5)])).forecast == nil, "No device storage: no forecast")
    }

    @Test func theTimelineKeepsTheLastSixtyMonthsAndStartsFromWhatCameBefore() throws {
        var monthly: [Date: LibraryScan.Bucket] = [:]
        for back in 0..<70 { monthly[Self.calendar.date(byAdding: .month, value: -back, to: month(2025, 11))!] = .init(count: 1, bytes: 10) }
        let timeline = try #require(make(profile: profile(monthly)).timeline)
        #expect(timeline.count == DashboardStats.timelineMonths)
        #expect(timeline.first?.total == 110, "Ten earlier months fold into the first point")
        #expect(timeline.last?.total == 700)
        #expect(zip(timeline, timeline.dropFirst()).allSatisfy { $0.total <= $1.total })
    }

    @Test func compositionIsBiggestFirstWithTiesInKindOrder() throws {
        let library = LibraryProfile(composition: [
            .photo: .init(count: 3, bytes: 500), .screenshot: .init(count: 9, bytes: 500), .video: .init(count: 1, bytes: 1_000),
        ], monthly: [month(2025, 1): .init(count: 13, bytes: 2_000)])
        let slices = try #require(make(profile: library).composition)
        #expect(slices.map(\.kind) == [.video, .screenshot, .photo])
        #expect(slices.map(\.share) == [0.5, 0.25, 0.25])
    }

    @Test func insightsPickTheBusiestMonthAndRecentYears() throws {
        var monthly: [Date: LibraryScan.Bucket] = [month(2024, 3): .init(count: 50, bytes: 1), month(2025, 3): .init(count: 50, bytes: 1)]
        for year in 2014...2023 { monthly[month(year, 6)] = .init(count: 5, bytes: 1) }
        let insights = try #require(make(profile: profile(monthly, oldest: month(2014, 6))).insights)
        #expect(insights.busiestMonth == month(2025, 3), "A tie goes to the more recent month")
        #expect(insights.busiestMonthCount == 50)
        #expect(insights.perYear.map(\.year) == Array(2018...2025))
        #expect(insights.oldestUnreviewedYear == 2014)
    }

    @Test func aSnapshotCachedBeforeTheseSectionsStillDecodes() throws {
        let older = DashboardSnapshot(totalCleared: 5, computedAt: now)
        let json = try JSONEncoder().encode(older)
        let keys = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any]).keys
        #expect(!keys.contains("timeline") && !keys.contains("activity"))
        #expect(try JSONDecoder().decode(DashboardSnapshot.self, from: json) == older)
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

/// The mock builder, but the first scan waits for `release()`. `@unchecked` is safe: every access holds `lock`.
private final class SlowScanBuilder: FeedBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var scans = 0
    private var waiting: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { lock.withLock { waiting != nil } }

    func makeSession(number: Int, options: FeedOptions) async -> Session { Session(number: number, cards: []) }

    func libraryScan(excluding: Set<LibraryItem.ID>) async -> LibraryScan? {
        let first = lock.withLock { scans += 1; return scans == 1 }
        if first { await withCheckedContinuation { continuation in lock.withLock { waiting = continuation } } }
        return MockFeedBuilder.scan
    }

    func release() {
        let continuation = lock.withLock { defer { waiting = nil }; return waiting }
        continuation?.resume()
    }
}

/// The dashboard's cache and refresh.
@MainActor
struct DashboardControllerTests {
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A delete lands while a refresh is still scanning. The refresh it asks for runs again rather than
    /// handing back numbers read before the delete.
    @Test func aRefreshAskedForMidRunIncludesWhatChangedSince() async throws {
        let store = InMemoryProgressStore()
        let builder = SlowScanBuilder()
        let controller = DashboardController(builder: builder, store: store, cacheURL: nil, now: { now })
        let first = Task { await controller.refresh(reviewedFraction: 0) }
        await until { builder.isWaiting }

        store.recordCleanup([CleanupEntry(at: now, category: .photo, count: 2, bytes: 700)])
        let second = Task { await controller.refresh(reviewedFraction: 0) }
        builder.release()
        await first.value
        await second.value

        #expect(controller.snapshot?.totalCleared == 700)
        #expect(!controller.isRefreshing)
    }

    @Test func aResetDropsTheNumbersOfARefreshAlreadyGoing() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = InMemoryProgressStore()
        store.recordCleanup([CleanupEntry(at: now, category: .photo, count: 1, bytes: 500)])
        let builder = SlowScanBuilder()
        let controller = DashboardController(builder: builder, store: store, cacheURL: url, now: { now })
        let running = Task { await controller.refresh(reviewedFraction: 0) }
        await until { builder.isWaiting }

        controller.clear()
        builder.release()
        await running.value

        #expect(controller.snapshot == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

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
