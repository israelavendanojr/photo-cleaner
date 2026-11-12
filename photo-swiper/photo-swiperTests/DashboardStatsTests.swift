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

    private func make(_ history: [CleanupEntry], scan: LibraryScan? = nil) -> DashboardSnapshot {
        DashboardStats.make(history: history, scan: scan, now: now, calendar: Self.calendar)
    }

    @Test func nothingClearedIsAllZero() {
        let snapshot = make([])
        #expect(snapshot.totalCleared == 0)
        #expect(snapshot.opportunities.isEmpty)
        #expect(snapshot.computedAt == now)
    }

    @Test func weekOverWeekIsTheLastSevenDaysAgainstTheSevenBefore() {
        let snapshot = make([entry(0.5, 100), entry(6.9, 20), entry(7.1, 5), entry(13.9, 1), entry(15, 1_000)])
        #expect(snapshot.totalCleared == 1_126)
        #expect(snapshot.clearedThisWeek == 120)
        #expect(snapshot.clearedLastWeek == 6)
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
}

/// The library's composition and the activity heatmap.
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

    private func make(history: [CleanupEntry] = [], profile: LibraryProfile? = nil) -> DashboardSnapshot {
        DashboardStats.make(history: history, scan: LibraryScan(profile: profile), now: now, calendar: Self.calendar)
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

    @Test func aLoneCleanupDayIsTheDarkestAndTiesShareALevel() throws {
        let lone = try #require(make(history: [cleanup(1, 10)]).activity)
        #expect(lone.days.map(\.level).max() == 4)
        let tied = try #require(make(history: [cleanup(1, 10), cleanup(2, 10), cleanup(3, 5)]).activity)
        let levels = Dictionary(tied.days.map { ($0.bytes, $0.level) }, uniquingKeysWith: { first, _ in first })
        #expect(levels[10] == 4 && levels[5] == 2)
    }

    /// In Beirut, DST starts at midnight: the last Sunday of March begins at 01:00. Days and weeks after it
    /// still line up, with weeks starting on Sunday.
    @Test func daysAndWeeksSurviveDSTStartingAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Beirut")!
        calendar.firstWeekday = 1
        let date = { (month: Int, day: Int) in calendar.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))! }
        #expect(calendar.component(.hour, from: calendar.startOfDay(for: date(3, 30))) == 1, "Midnight doesn't exist that day")
        let history = [date(3, 25), date(4, 1), date(4, 8)].map { CleanupEntry(at: $0, category: .photo, count: 1, bytes: 100) }

        let activity = DashboardStats.activity(history, now: date(4, 9), calendar: calendar)
        #expect(activity.activeDays == 3)
        #expect(activity.days.filter { $0.bytes > 0 }.count == 3)
        #expect(activity.days.allSatisfy { $0.date == calendar.startOfDay(for: $0.date) })
        #expect(activity.streakWeeks == 3)
    }

    // MARK: Library

    @Test func compositionIsBiggestFirstWithTiesInKindOrder() throws {
        let library = LibraryProfile(composition: [
            .photo: .init(count: 3, bytes: 500), .screenshot: .init(count: 9, bytes: 500), .video: .init(count: 1, bytes: 1_000),
        ])
        let slices = try #require(make(profile: library).composition)
        #expect(slices.map(\.kind) == [.video, .screenshot, .photo])
        #expect(slices.map(\.share) == [0.5, 0.25, 0.25])
    }

    @Test func aSnapshotCachedBeforeTheseSectionsStillDecodes() throws {
        let older = DashboardSnapshot(totalCleared: 5, computedAt: now)
        let json = try JSONEncoder().encode(older)
        let keys = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any]).keys
        #expect(!keys.contains("composition") && !keys.contains("activity"))
        #expect(try JSONDecoder().decode(DashboardSnapshot.self, from: json) == older)
    }

    /// A snapshot cached by the build before this one, with sections that are gone now (health, the running
    /// total, weekly totals, the timeline, the forecast, insights). It still decodes; the extra keys are ignored.
    @Test func aSnapshotCachedWithSectionsThatAreGoneStillDecodes() throws {
        let json = """
        {"totalCleared":8120000000,"clearedThisWeek":2820000000,"clearedLastWeek":0,
         "cumulative":[{"date":784000000,"total":0},{"date":784086400,"total":8120000000}],
         "weekly":[{"date":784000000,"bytes":8120000000}],
         "opportunities":[{"category":"video","count":38,"bytes":6120000000}],
         "health":0.53,"scanPercent":86,"computedAt":784100000,
         "timeline":[{"date":784000000,"total":64000000000}],
         "forecast":{"total":128000000000,"available":18000000000,"libraryBytes":64000000000,"bytesPerDay":1000000},
         "composition":[{"kind":"video","count":1430,"bytes":24300000000,"share":0.38}],
         "activity":{"days":[{"date":784000000,"bytes":100,"level":4}],"activeDays":1,"streakWeeks":1},
         "insights":{"busiestMonth":784000000,"busiestMonthCount":400,"perYear":[{"year":2025,"count":400}],"oldestUnreviewedYear":2020}}
        """
        let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.totalCleared == 8_120_000_000)
        #expect(snapshot.clearedThisWeek == 2_820_000_000)
        #expect(snapshot.scanPercent == 86)
        #expect(snapshot.composition?.first?.kind == .video)
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

    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>) async -> LibraryScan? {
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
        let first = Task { await controller.refresh() }
        await until { builder.isWaiting }

        store.recordCleanup([CleanupEntry(at: now, category: .photo, count: 2, bytes: 700)])
        let second = Task { await controller.refresh() }
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
        let running = Task { await controller.refresh() }
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

        await controller.refresh()

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
        await controller.refresh()
        #expect(!controller.isStale)
        clock = now.addingTimeInterval(DashboardController.staleAfter + 1)
        #expect(controller.isStale)
    }

    @Test func clearingForgetsTheCache() async {
        let url = cacheURL()
        let controller = DashboardController(builder: MockFeedBuilder(), store: InMemoryProgressStore(), cacheURL: url, now: { now })
        await controller.refresh()
        controller.clear()
        #expect(controller.snapshot == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }
}
