import Foundation

/// Everything the dashboard shows that takes work to compute, worked out off the main thread and cached
/// between launches so the Library tab opens at once.
struct DashboardSnapshot: Equatable, Codable, Sendable {
    /// One row of the library card: what it counts and how big that is.
    struct Row: Equatable, Codable, Sendable, Identifiable {
        var focus: FocusTarget
        var count: Int
        /// Duplicates and similar shots count only the extras; everything else counts in full.
        var bytes: Int64
        var id: FocusTarget { focus }
    }

    /// This week's space cleared against last week's.
    struct WeeklyChange: Equatable, Sendable {
        /// This week minus last week.
        var delta: Int64
        /// The change as a share of last week; nil when last week cleared nothing, so there's nothing to compare to.
        var percent: Double?
        var isDown: Bool { delta < 0 }
    }

    var totalCleared: Int64 = 0
    /// The last 7 days, and the 7 before them.
    var clearedThisWeek: Int64 = 0
    var clearedLastWeek: Int64 = 0
    /// How far library analysis has got, 0...100. Nil once it's complete.
    var scanPercent: Int?
    var computedAt: Date
    // Optional, so a snapshot cached before them still decodes. Fields cached by older builds that are
    // gone now (health, cumulative, weekly, timeline, forecast, insights, composition, chips, and
    // `activity` and `reviews`, the old heatmaps) are ignored when decoding.
    /// Biggest first, saved for later last, only those with something in them (`DashboardStats.rows`).
    var rows: [Row]?

    var weeklyChange: WeeklyChange? { DashboardStats.weeklyChange(this: clearedThisWeek, last: clearedLastWeek) }
}

/// Builds a `DashboardSnapshot`. Pure: no PhotoKit, no store, time passed in.
enum DashboardStats {
    static func make(history: [CleanupEntry], scan: LibraryScan?, now: Date) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot(computedAt: now)
        snapshot.totalCleared = history.reduce(0) { $0 + $1.bytes }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        snapshot.clearedThisWeek = history.filter { $0.at > weekAgo && $0.at <= now }.reduce(0) { $0 + $1.bytes }
        snapshot.clearedLastWeek = history.filter { $0.at > twoWeeksAgo && $0.at <= weekAgo }.reduce(0) { $0 + $1.bytes }
        if let scan {
            snapshot.rows = rows(scan)
            snapshot.scanPercent = scan.scanPercent
        }
        return snapshot
    }

    /// Nil when neither week cleared anything, so there's no line to show.
    static func weeklyChange(this: Int64, last: Int64) -> DashboardSnapshot.WeeklyChange? {
        guard this > 0 || last > 0 else { return nil }
        return DashboardSnapshot.WeeklyChange(delta: this - last, percent: last > 0 ? Double(this - last) / Double(last) : nil)
    }

    /// The library card's rows, biggest first, leaving out any with nothing in them. Equal sizes keep
    /// `FocusTarget.listOrder`. Saved for later always goes last: it's what the user put off, not what the
    /// library holds, so it shouldn't push what's worth a look down.
    static func rows(_ scan: LibraryScan) -> [DashboardSnapshot.Row] {
        let rows = FocusTarget.listOrder.enumerated().compactMap { offset, focus -> (offset: Int, row: DashboardSnapshot.Row)? in
            guard let bucket = scan.bucket(for: focus), bucket.count > 0 else { return nil }
            return (offset, DashboardSnapshot.Row(focus: focus, count: bucket.count, bytes: bucket.bytes))
        }
        return rows.sorted { first, second in
            let firstLast = first.row.focus == .savedForLater, secondLast = second.row.focus == .savedForLater
            if firstLast != secondLast { return secondLast }
            if first.row.bytes != second.row.bytes { return first.row.bytes > second.row.bytes }
            return first.offset < second.offset
        }.map(\.row)
    }
}
