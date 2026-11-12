import Foundation

/// Everything the dashboard shows that takes work to compute, worked out off the main thread and cached
/// between launches so the Library tab opens at once.
struct DashboardSnapshot: Equatable, Codable, Sendable {
    /// Cleared space up to the end of one day.
    struct DayPoint: Equatable, Codable, Sendable, Identifiable {
        /// The start of the day.
        var date: Date
        /// Everything cleared up to and including this day.
        var total: Int64
        var id: Date { date }
    }

    /// Space cleared in one calendar week.
    struct WeekPoint: Equatable, Codable, Sendable, Identifiable {
        /// The start of the week.
        var date: Date
        var bytes: Int64
        var id: Date { date }
    }

    /// One kind of clutter still in the library.
    struct Opportunity: Equatable, Codable, Sendable, Identifiable {
        var category: CleanupCategory
        var count: Int
        var bytes: Int64
        var id: CleanupCategory { category }
    }

    var totalCleared: Int64 = 0
    /// The last 7 days, and the 7 before them.
    var clearedThisWeek: Int64 = 0
    var clearedLastWeek: Int64 = 0
    /// Running total by day, from the day before the first cleanup (at zero) to today.
    var cumulative: [DayPoint] = []
    /// Every calendar week from the first cleanup's to this one, empty weeks included, at most `maxWeeks`.
    var weekly: [WeekPoint] = []
    /// Biggest first.
    var opportunities: [Opportunity] = []
    /// 0...1, nil until the library has been looked at. See `DashboardStats.health`.
    var health: Double?
    /// How far library analysis has got, 0...100. Nil once it's complete.
    var scanPercent: Int?
    var computedAt: Date

    var recoverableBytes: Int64 { opportunities.reduce(0) { $0 + $1.bytes } }
}

/// Builds a `DashboardSnapshot`. Pure: no PhotoKit, no store, time and calendar passed in.
enum DashboardStats {
    static let maxWeeks = 26

    static func make(
        history: [CleanupEntry], scan: LibraryScan?, reviewedFraction: Double, now: Date, calendar: Calendar = .current
    ) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot(computedAt: now)
        snapshot.totalCleared = history.reduce(0) { $0 + $1.bytes }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        snapshot.clearedThisWeek = history.filter { $0.at > weekAgo && $0.at <= now }.reduce(0) { $0 + $1.bytes }
        snapshot.clearedLastWeek = history.filter { $0.at > twoWeeksAgo && $0.at <= weekAgo }.reduce(0) { $0 + $1.bytes }
        snapshot.cumulative = cumulative(history, now: now, calendar: calendar)
        snapshot.weekly = weekly(history, now: now, calendar: calendar)
        if let scan {
            snapshot.opportunities = opportunities(scan)
            snapshot.scanPercent = scan.scanPercent
            snapshot.health = health(recoverable: snapshot.recoverableBytes, of: scan.indexedBytes, reviewedFraction: reviewedFraction)
        }
        return snapshot
    }

    /// Kinds with something to clear, biggest first; equal sizes keep `CleanupCategory`'s order.
    static func opportunities(_ scan: LibraryScan) -> [DashboardSnapshot.Opportunity] {
        let order: [CleanupCategory: Int] = Dictionary(uniqueKeysWithValues: CleanupCategory.allCases.enumerated().map { ($1, $0) })
        let found: [DashboardSnapshot.Opportunity] = scan.buckets.compactMap { category, bucket in
            bucket.count > 0 ? DashboardSnapshot.Opportunity(category: category, count: bucket.count, bytes: bucket.bytes) : nil
        }
        return found.sorted { first, second in
            if first.bytes != second.bytes { return first.bytes > second.bytes }
            return order[first.category, default: 0] < order[second.category, default: 0]
        }
    }

    /// Half how little of the library is clutter, half how much of it has been reviewed. Either alone
    /// misleads: a fresh library with no clutter found yet isn't "done", and reviewing everything while
    /// keeping every duplicate isn't healthy. Nil when nothing has been analyzed yet.
    static func health(recoverable: Int64, of indexedBytes: Int64, reviewedFraction: Double) -> Double? {
        guard indexedBytes > 0 else { return nil }
        let clutter = min(1, max(0, Double(recoverable) / Double(indexedBytes)))
        let reviewed = min(1, max(0, reviewedFraction))
        return 0.5 * (1 - clutter) + 0.5 * reviewed
    }

    private static func cumulative(_ history: [CleanupEntry], now: Date, calendar: Calendar) -> [DashboardSnapshot.DayPoint] {
        guard let first = history.map(\.at).min() else { return [] }
        let byDay = Dictionary(grouping: history) { calendar.startOfDay(for: $0.at) }.mapValues { $0.reduce(0) { $0 + $1.bytes } }
        let start = calendar.startOfDay(for: first)
        let today = max(start, calendar.startOfDay(for: now))
        var points = [DashboardSnapshot.DayPoint]()
        if let before = calendar.date(byAdding: .day, value: -1, to: start) { points.append(.init(date: before, total: 0)) }
        var total: Int64 = 0
        for day in byDay.keys.sorted() {
            total += byDay[day] ?? 0
            points.append(.init(date: day, total: total))
        }
        if points.last?.date != today { points.append(.init(date: today, total: total)) }
        return points
    }

    private static func weekly(_ history: [CleanupEntry], now: Date, calendar: Calendar) -> [DashboardSnapshot.WeekPoint] {
        guard let first = history.map(\.at).min(),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: max(first, now))?.start else { return [] }
        let byWeek = Dictionary(grouping: history) { calendar.dateInterval(of: .weekOfYear, for: $0.at)?.start ?? firstWeek }
            .mapValues { $0.reduce(0) { $0 + $1.bytes } }
        var weeks = [DashboardSnapshot.WeekPoint]()
        var week = thisWeek
        while week >= firstWeek, weeks.count < maxWeeks {
            weeks.append(.init(date: week, bytes: byWeek[week] ?? 0))
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return weeks.reversed()
    }
}
