import Foundation
import Observation
import OSLog

/// The Library tab's dashboard: the cleanup history and what's left to clear, worked out off the main
/// thread and cached on disk, so the tab shows the last numbers at once and updates when they're in.
/// `FeedViewModel` owns it and passes in the reviewed fraction, read fresh at each refresh.
@Observable
@MainActor
final class DashboardController {
    /// Older than this, the dashboard refreshes when it's shown.
    static let staleAfter: TimeInterval = 10 * 60
    private static let log = Logger.app(category: "dashboard")

    /// The last numbers worked out, from this launch or the cache. Nil before the first refresh on a new install.
    private(set) var snapshot: DashboardSnapshot?
    /// A refresh is running.
    private(set) var isRefreshing = false

    private let builder: any FeedBuilding
    private let store: any ProgressStoring
    /// Where the snapshot is cached between launches. Nil keeps it in memory (tests, previews).
    private let cacheURL: URL?
    private let calendar: Calendar
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?

    init(builder: any FeedBuilding, store: any ProgressStoring, cacheURL: URL?, calendar: Calendar = .current,
         now: @escaping () -> Date) {
        self.builder = builder
        self.store = store
        self.cacheURL = cacheURL
        self.calendar = calendar
        self.now = now
        snapshot = cacheURL.flatMap(Self.readCache)
    }

    /// The app's cache file.
    static var defaultCacheURL: URL { .cachesDirectory.appending(path: "dashboard-snapshot.json") }

    /// Missing, or older than `staleAfter`.
    var isStale: Bool {
        guard let snapshot else { return true }
        return now().timeIntervalSince(snapshot.computedAt) > Self.staleAfter
    }

    /// Works the numbers out again. A refresh already running is joined rather than doubled.
    func refresh(reviewedFraction: Double) async {
        if let refreshTask { return await refreshTask.value }
        isRefreshing = true
        let task = Task { await self.compute(reviewedFraction: reviewedFraction) }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    /// Forgets the numbers and the cache, after progress is reset.
    func clear() {
        snapshot = nil
        guard let cacheURL else { return }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func compute(reviewedFraction: Double) async {
        // The store lives on the main actor; the scan and the sums don't.
        let history = store.cleanupHistory()
        let excluding = store.excludedFromNewSession(asOf: now())
        let scan = await builder.libraryScan(excluding: excluding)
        let now = now(), calendar = calendar, cacheURL = cacheURL
        let next = await Task.detached(priority: .utility) {
            let snapshot = DashboardStats.make(history: history, scan: scan, reviewedFraction: reviewedFraction, now: now, calendar: calendar)
            if let cacheURL { Self.writeCache(snapshot, to: cacheURL) }
            return snapshot
        }.value
        snapshot = next
    }

    private nonisolated static func readCache(_ url: URL) -> DashboardSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DashboardSnapshot.self, from: data)
    }

    private nonisolated static func writeCache(_ snapshot: DashboardSnapshot, to url: URL) {
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            Logger.app(category: "dashboard").error("Couldn't cache the dashboard: \(error)")
        }
    }
}
