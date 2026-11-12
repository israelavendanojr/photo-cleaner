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
        #expect(snapshot.chips == nil)
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

    // MARK: Chips

    @Test func chipsKeepTheirOrderAndHideTheEmptyOnes() {
        let scan = LibraryScan(buckets: [
            .screenshot: .init(count: 9, bytes: 500),
            .video: .init(count: 1, bytes: 900),
            .duplicate: .init(count: 2, bytes: 500),
            .burst: .init(count: 0, bytes: 0),
        ], focusBuckets: [.savedForLater: .init(count: 3, bytes: 30), .livePhotos: .init()])
        let chips = DashboardStats.chips(scan)
        #expect(chips.map(\.focus) == [.category(.duplicate), .category(.video), .category(.screenshot), .savedForLater])
        #expect(chips.map(\.bytes) == [500, 900, 500, 30])
    }

    @Test func theDefaultChipIsTheMostToRecoverWithTiesToTheEarlierOne() {
        func chip(_ focus: FocusTarget, _ bytes: Int64) -> DashboardSnapshot.Chip {
            DashboardSnapshot.Chip(focus: focus, count: 1, bytes: bytes, thumbnails: [])
        }
        let chips = [
            chip(.category(.duplicate), 500), chip(.category(.video), 900), chip(.allVideos, 5_000),
            chip(.category(.screenshot), 900), chip(.savedForLater, 9_000),
        ]
        #expect(DashboardStats.defaultChip(chips) == .category(.video),
                "All videos and saved for later are the library's own sizes, not space to recover; a tie goes to the earlier chip")
        #expect(DashboardStats.defaultChip([chip(.livePhotos, 10), chip(.savedForLater, 20)]) == .livePhotos,
                "With nothing to recover, the first chip")
        #expect(DashboardStats.defaultChip([]) == nil)
    }

    @Test func theSnapshotCarriesTheChipsAndTheirDefault() throws {
        let snapshot = make([], scan: MockFeedBuilder.scan)
        let chips = try #require(snapshot.chips)
        #expect(chips.count == FocusTarget.chipOrder.count)
        #expect(snapshot.defaultChip == .category(.video))
        #expect(chips.allSatisfy { !$0.thumbnails.isEmpty })
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

    /// `count` reviews on the day `daysAgo` days back.
    private func reviewed(_ entries: [(daysAgo: Double, count: Int)]) -> [Date: Int] {
        Dictionary(entries.map { (Self.calendar.startOfDay(for: now.addingTimeInterval(-$0.daysAgo * day)), $0.count) }, uniquingKeysWith: +)
    }

    private func make(reviews: [Date: Int] = [:], profile: LibraryProfile? = nil) -> DashboardSnapshot {
        DashboardStats.make(history: [], scan: LibraryScan(profile: profile), reviews: reviews, now: now, calendar: Self.calendar)
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

    @Test func samplesAreTheBiggestFewWithTiesByID() {
        var library: [LibraryItem.ID: AssetFeatures] = [:]
        for (id, bytes) in [("a", 10), ("b", 50), ("c", 50), ("d", 5), ("e", 40), ("f", 30), ("g", 1)] {
            library[id] = features(bytes: Int64(bytes), screenshot: true)
        }
        let scan = LibraryScan.make(features: library, excluding: [], duplicates: [], similar: [], scanPercent: nil,
                                    reference: { .bundled($0) })
        #expect(scan.samples[.category(.screenshot)] == ["b", "c", "e", "f", "a"].map(ImageReference.bundled))
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
        #expect(snapshot.defaultChip == .category(.video))
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
