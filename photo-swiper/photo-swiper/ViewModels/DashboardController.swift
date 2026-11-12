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
    /// Nil where there's no device to ask (tests): no forecast.
    private let storage: (any DeviceStorageReading)?
    /// Where the snapshot is cached between launches. Nil keeps it in memory (tests, previews).
    private let cacheURL: URL?
    private let calendar: Calendar
    private let now: () -> Date
    private var running: Task<Void, Never>?
    /// Each refresh asked for gets the next number; `completed` is the newest one whose numbers are in.
    private var requested = 0
    private var completed = 0
    /// Results of runs started at or before this are dropped: `clear()` came after them.
    private var clearedAt = 0
    private var latest = Inputs(reviewedFraction: 0, excluding: [], removed: [])

    private struct Inputs {
        var reviewedFraction: Double
        var excluding: Set<LibraryItem.ID>
        var removed: Set<LibraryItem.ID>
    }

    init(builder: any FeedBuilding, store: any ProgressStoring, storage: (any DeviceStorageReading)? = nil, cacheURL: URL?,
         calendar: Calendar = .current, now: @escaping () -> Date) {
        self.builder = builder
        self.store = store
        self.storage = storage
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

    /// Works the numbers out again and returns once they include everything up to this call.
    ///
    /// Requests coalesce rather than join: one made while a run is going waits for it, then one more run
    /// covers it and any others that came in meanwhile, so a delete made mid-run is never left out.
    /// - Parameter excluding: Items decided or in the deck, from what the caller has in memory. The builder
    ///   adds what its last page excluded, so this never has to read every saved decision.
    /// - Parameter removed: Items deleted or gone that the index may not have dropped yet.
    func refresh(reviewedFraction: Double, excluding: Set<LibraryItem.ID> = [], removed: Set<LibraryItem.ID> = []) async {
        requested += 1
        let mine = requested
        latest = Inputs(reviewedFraction: reviewedFraction, excluding: excluding, removed: removed)
        while completed < mine {
            if let running {
                await running.value
                continue
            }
            let target = requested
            let inputs = latest
            isRefreshing = true
            // The run settles its own bookkeeping before it finishes, so whichever waiter wakes first
            // sees it done; otherwise a waiter could keep re-awaiting a finished task on the main actor.
            let task = Task {
                await self.compute(inputs, target: target)
                self.completed = max(self.completed, target)
                self.running = nil
                self.isRefreshing = false
            }
            running = task
            await task.value
        }
    }

    /// Forgets the numbers and the cache, after progress is reset. A run already going is dropped.
    func clear() {
        clearedAt = requested
        snapshot = nil
        guard let cacheURL else { return }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func compute(_ inputs: Inputs, target: Int) async {
        // The history is a small read on the main actor; the scan and the sums aren't on it.
        let history = store.cleanupHistory()
        let scan = await builder.libraryScan(excluding: inputs.excluding, removed: inputs.removed)
        let now = now(), calendar = calendar, reviewed = inputs.reviewedFraction, storage = storage
        let next = await Task.detached(priority: .utility) {
            // Free space is only read when there's a library to set it against, for the storage bar.
            let device = scan?.profile == nil ? nil : storage?.current()
            return DashboardStats.make(history: history, scan: scan, reviewedFraction: reviewed, storage: device,
                                       now: now, calendar: calendar)
        }.value
        guard target > clearedAt else { return }
        snapshot = next
        guard let cacheURL else { return }
        await Task.detached(priority: .utility) { Self.writeCache(next, to: cacheURL) }.value
        // A reset during the write: the numbers it wrote are gone too.
        if target <= clearedAt { try? FileManager.default.removeItem(at: cacheURL) }
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
