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
        #expect(snapshot.rows == nil)
        #expect(snapshot.computedAt == now)
    }

    @Test func weekOverWeekIsTheLastSevenDaysAgainstTheSevenBefore() {
        let snapshot = make([entry(0.5, 100), entry(6.9, 20), entry(7.1, 5), entry(13.9, 1), entry(15, 1_000)])
        #expect(snapshot.totalCleared == 1_126)
        #expect(snapshot.clearedThisWeek == 120)
        #expect(snapshot.clearedLastWeek == 6)
    }

    // MARK: Week over week

    @Test func noChangeLineWhenNeitherWeekClearedAnything() {
        #expect(DashboardStats.weeklyChange(this: 0, last: 0) == nil)
        #expect(make([entry(20, 500)]).weeklyChange == nil, "Older cleanups don't make a line")
    }

    @Test(arguments: [
        (Int64(1_620), Int64(1_200), Int64(420), 0.35),
        (Int64(300), Int64(400), Int64(-100), -0.25),
        (Int64(0), Int64(400), Int64(-400), -1.0),
        (Int64(500), Int64(500), Int64(0), 0.0),
    ])
    func theChangeIsThisWeekAgainstLast(this: Int64, last: Int64, delta: Int64, percent: Double) throws {
        let change = try #require(DashboardStats.weeklyChange(this: this, last: last))
        #expect(change.delta == delta)
        #expect(abs(try #require(change.percent) - percent) < 0.000_001)
        #expect(change.isDown == (delta < 0))
    }

    @Test func nothingLastWeekHasNoPercentage() throws {
        let change = try #require(DashboardStats.weeklyChange(this: 1_200, last: 0))
        #expect(change.delta == 1_200)
        #expect(change.percent == nil)
        #expect(!change.isDown)
    }

    @Test func theSnapshotsChangeUsesItsTwoWeeks() throws {
        let change = try #require(make([entry(1, 300), entry(8, 200)]).weeklyChange)
        #expect(change.delta == 100)
        #expect(change.percent == 0.5)
    }

    // MARK: Rows

    @Test func rowsAreBiggestFirstWithTiesInListOrderAndEmptyOnesHidden() {
        let scan = LibraryScan(buckets: [
            .screenshot: .init(count: 9, bytes: 500),
            .similar: .init(count: 1, bytes: 900),
            .duplicate: .init(count: 2, bytes: 500),
            .burst: .init(count: 0, bytes: 0),
        ], focusBuckets: [.allVideos: .init(count: 4, bytes: 2_000), .livePhotos: .init()])
        let rows = DashboardStats.rows(scan)
        #expect(rows.map(\.focus) == [.allVideos, .category(.similar), .category(.duplicate), .category(.screenshot)],
                "Equal sizes keep the list's order; empty rows are left out")
        #expect(rows.map(\.bytes) == [2_000, 900, 500, 500])
    }

    @Test func largeVideosAreNotARow() {
        let scan = LibraryScan(buckets: [.video: .init(count: 3, bytes: 900)], focusBuckets: [.allVideos: .init(count: 5, bytes: 1_000)])
        #expect(DashboardStats.rows(scan).map(\.focus) == [.allVideos], "They're already in Videos")
    }

    @Test func savedForLaterIsAlwaysLast() {
        let scan = LibraryScan(buckets: [.screenshot: .init(count: 1, bytes: 10), .photo: .init(count: 3, bytes: 300)],
                               focusBuckets: [.savedForLater: .init(count: 3, bytes: 9_000)])
        #expect(DashboardStats.rows(scan).map(\.focus) == [.category(.photo), .category(.screenshot), .savedForLater],
                "Even when it's the biggest")
    }

    @Test func theSnapshotCarriesEveryRowWithSomethingInIt() throws {
        let snapshot = make([], scan: MockFeedBuilder.scan)
        let rows = try #require(snapshot.rows)
        #expect(rows.count == FocusTarget.listOrder.count)
        #expect(rows.last?.focus == .savedForLater)
        #expect(rows.dropLast().map(\.bytes) == rows.dropLast().map(\.bytes).sorted(by: >))
    }
}

/// The activity heatmap, and decoding older caches.
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

    /// `count` reviews on the day `daysAgo` days back.
    private func reviewed(_ entries: [(daysAgo: Double, count: Int)]) -> [Date: Int] {
        Dictionary(entries.map { (Self.calendar.startOfDay(for: now.addingTimeInterval(-$0.daysAgo * day)), $0.count) }, uniquingKeysWith: +)
    }

    private func make(reviews: [Date: Int] = [:]) -> DashboardSnapshot {
        DashboardStats.make(history: [], scan: LibraryScan(), reviews: reviews, now: now, calendar: Self.calendar)
    }

    // MARK: Reviews

    @Test func theHeatmapRunsSixteenWholeWeeksToToday() throws {
        let activity = try #require(make().reviews)
        #expect(activity.days.count == 15 * 7 + 3, "Fifteen whole weeks, then Monday to Wednesday")
        #expect(Self.calendar.component(.weekday, from: try #require(activity.days.first).date) == 2)
        #expect(activity.days.first?.date == DashboardStats.activityStart(now: now, calendar: Self.calendar))
        #expect(activity.days.last?.date == Self.calendar.startOfDay(for: now))
        #expect(activity.days.allSatisfy { $0.level == 0 })
        #expect(activity.total == 0)
    }

    @Test func levelsAreQuartilesOfTheDaysWithReviews() throws {
        let activity = try #require(make(reviews: reviewed([(1, 10), (2, 20), (3, 30), (4, 40)])).reviews)
        let levels = Dictionary(activity.days.map { ($0.count, $0.level) }, uniquingKeysWith: { first, _ in first })
        #expect(levels[10] == 1 && levels[20] == 2 && levels[30] == 3 && levels[40] == 4)
        #expect(levels[0] == 0)
        #expect(activity.activeDays == 4)
        #expect(activity.total == 100)
    }

    @Test func reviewsBeforeTheFirstWeekArentShown() throws {
        let activity = try #require(make(reviews: reviewed([(1, 5), (200, 50)])).reviews)
        #expect(activity.total == 5)
        #expect(activity.activeDays == 1)
    }

    @Test func aLoneReviewDayIsTheDarkestAndTiesShareALevel() throws {
        let lone = try #require(make(reviews: reviewed([(1, 10)])).reviews)
        #expect(lone.days.map(\.level).max() == 4)
        let tied = try #require(make(reviews: reviewed([(1, 10), (2, 10), (3, 5)])).reviews)
        let levels = Dictionary(tied.days.map { ($0.count, $0.level) }, uniquingKeysWith: { first, _ in first })
        #expect(levels[10] == 4 && levels[5] == 2)
    }

    /// In Beirut, DST starts at midnight: the last Sunday of March begins at 01:00. Days after it still
    /// line up with the store's days (`startOfDay`), with weeks starting on Sunday.
    @Test func daysSurviveDSTStartingAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Beirut")!
        calendar.firstWeekday = 1
        let date = { (month: Int, day: Int) in calendar.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))! }
        #expect(calendar.component(.hour, from: calendar.startOfDay(for: date(3, 30))) == 1, "Midnight doesn't exist that day")
        let reviews = Dictionary(uniqueKeysWithValues: [date(3, 25), date(3, 30), date(4, 8)].map { (calendar.startOfDay(for: $0), 3) })

        let activity = DashboardStats.activity(reviews, now: date(4, 9), calendar: calendar)
        #expect(activity.activeDays == 3)
        #expect(activity.days.filter { $0.count > 0 }.count == 3)
        #expect(activity.days.allSatisfy { $0.date == calendar.startOfDay(for: $0.date) })
    }

    // MARK: Caches

    @Test func aSnapshotCachedBeforeTheseSectionsStillDecodes() throws {
        let older = DashboardSnapshot(totalCleared: 5, computedAt: now)
        let json = try JSONEncoder().encode(older)
        let keys = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any]).keys
        #expect(!keys.contains("rows") && !keys.contains("reviews"))
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
        #expect(snapshot.rows == nil)
    }

    /// A snapshot cached by an earlier build of this dashboard, with the library card's chips, their thumbnails, the chip
    /// picked first and the composition bar. It still decodes, with no rows until the next refresh.
    @Test func aSnapshotCachedWithChipsStillDecodes() throws {
        let json = """
        {"totalCleared":8120000000,"clearedThisWeek":2820000000,"clearedLastWeek":60000000,"scanPercent":86,
         "computedAt":784100000,
         "composition":[{"kind":"video","count":1430,"bytes":24300000000,"share":0.38}],
         "reviews":{"days":[{"date":784000000,"count":12,"level":4}],"activeDays":1,"total":12},
         "chips":[{"focus":{"category":{"_0":"video"}},"count":38,"bytes":6120000000,"thumbnails":[{"bundled":{"_0":"v1"}}]}],
         "defaultChip":{"category":{"_0":"video"}}}
        """
        let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.totalCleared == 8_120_000_000)
        #expect(snapshot.reviews?.total == 12)
        #expect(snapshot.rows == nil)
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

    @Test func analysisFindingsAreRowsAtFullSize() {
        var pocket = features(bytes: 10)
        pocket.sharpness = 5
        pocket.exposure = ExposureStats(mean: 3, darkFraction: 0.97, brightFraction: 0)
        var soft = features(bytes: 20)
        soft.sharpness = 12
        var receipt = features(bytes: 40)
        receipt.sharpness = 300
        receipt.isUtility = true
        var shot = features(bytes: 80, screenshot: true)
        shot.isUtility = true
        var favorite = features(bytes: 160, favorite: true)
        favorite.sharpness = 12
        let scan = LibraryScan.make(features: ["pocket": pocket, "soft": soft, "receipt": receipt, "shot": shot, "fav": favorite],
                                    excluding: [], duplicates: [], similar: [], scanPercent: nil)
        #expect(scan.bucket(for: .accidental) == .init(count: 1, bytes: 10), "Accidental, so not also blurry")
        #expect(scan.bucket(for: .blurry) == .init(count: 1, bytes: 20), "Favorites left out")
        #expect(scan.bucket(for: .documents) == .init(count: 1, bytes: 40), "A screenshot isn't a document")
        #expect(DashboardStats.rows(scan).map(\.focus).contains(.blurry))
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

    @Test func kindsCountInFullAndOverlapTheSuggestions() {
        let library: [LibraryItem.ID: AssetFeatures] = [
            "big-video": features(bytes: 80_000_000, video: true),
            "small-video": features(bytes: 2_000_000, video: true),
            "favorite-video": features(bytes: 9_000_000, video: true, favorite: true),
            "live-best": features(bytes: 4_000),
            "live-other": features(bytes: 3_000),
            "live-video": features(bytes: 7_000, video: true),
            "decided-live": features(bytes: 1_000),
            "photo": features(bytes: 6_000),
        ]
        let scan = LibraryScan.make(
            features: library, excluding: ["decided-live"], duplicates: [],
            similar: [PlannedGroup(ids: ["live-best", "live-other"], bestID: "live-best", reason: "")], scanPercent: nil,
            livePhotos: ["live-best", "live-other", "live-video", "decided-live"]
        )

        #expect(scan.bucket(for: .allVideos) == .init(count: 3, bytes: 82_007_000), "Every undecided video but favorites, any size")
        #expect(scan.bucket(for: .category(.video)) == .init(count: 1, bytes: 80_000_000), "Large videos are a subset")
        #expect(scan.bucket(for: .livePhotos) == .init(count: 2, bytes: 7_000), "Stills only, undecided, at full size")
        #expect(scan.bucket(for: .category(.similar)) == .init(count: 1, bytes: 3_000), "A Live Photo can be a similar extra too")
    }

    @Test func savedForLaterCountsThoughDecidedAndOnlyWhatsIndexed() {
        let library: [LibraryItem.ID: AssetFeatures] = ["later-a": features(bytes: 300), "later-b": features(bytes: 200), "kept": features(bytes: 9)]
        let scan = LibraryScan.make(features: library, excluding: ["later-a", "later-b", "kept"], duplicates: [], similar: [],
                                    scanPercent: nil, later: ["later-a", "later-b", "not-indexed"])
        #expect(scan.bucket(for: .savedForLater) == .init(count: 2, bytes: 500))
        #expect(scan.indexedCount == 0)
    }

    @Test func photosCountEveryUndecidedPlainPhotoInFull() {
        let library: [LibraryItem.ID: AssetFeatures] = [
            "photo": features(bytes: 6_000),
            "copy": features(bytes: 5_000),
            "original": features(bytes: 5_000),
            "favorite": features(bytes: 8_000, favorite: true),
            "decided": features(bytes: 9_000),
            "video": features(bytes: 2_000_000, video: true),
            "shot": features(bytes: 1_000, screenshot: true),
            "burst": features(bytes: 3_000, burst: true),
        ]
        let scan = LibraryScan.make(features: library, excluding: ["decided"],
                                    duplicates: [PlannedGroup(ids: ["original", "copy"], bestID: "original", reason: "")],
                                    similar: [], scanPercent: nil)
        #expect(scan.bucket(for: .category(.photo)) == .init(count: 3, bytes: 16_000),
                "Duplicates count too, as a photo focus shows them; favorites, decided items and other kinds don't")
        #expect(scan.bucket(for: .category(.duplicate)) == .init(count: 1, bytes: 5_000))
    }
}

/// The mock builder, but the first scan waits for `release()`. `@unchecked` is safe: every access holds `lock`.
private final class SlowScanBuilder: FeedBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var scans = 0
    private var waiting: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { lock.withLock { waiting != nil } }

    func makeSession(number: Int, options: FeedOptions) async -> Session { Session(number: number, cards: []) }

    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>, later: Set<LibraryItem.ID>) async -> LibraryScan? {
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
        #expect(snapshot.rows?.first?.focus == .allVideos)
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
