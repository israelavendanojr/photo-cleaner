import Foundation

/// Everything the dashboard shows that takes work to compute, worked out off the main thread and cached
/// between launches so the Library tab opens at once.
struct DashboardSnapshot: Equatable, Codable, Sendable {
    /// One kind of clutter still in the library.
    struct Opportunity: Equatable, Codable, Sendable, Identifiable {
        var category: CleanupCategory
        var count: Int
        var bytes: Int64
        var id: CleanupCategory { category }
    }

    /// One kind's share of the library.
    struct Slice: Equatable, Codable, Sendable, Identifiable {
        var kind: LibraryProfile.Kind
        var count: Int
        var bytes: Int64
        /// 0...1 of the library's bytes.
        var share: Double
        var id: LibraryProfile.Kind { kind }
    }

    /// Photos reviewed by day over the last `DashboardStats.activityWeeks` weeks, for the hero's heatmap.
    /// Reviewing counts, keeping included: it's the habit the dashboard rewards, not only what was cleared.
    struct Activity: Equatable, Codable, Sendable {
        struct Day: Equatable, Codable, Sendable, Identifiable {
            var date: Date
            var count: Int
            /// 0 for nothing reviewed, then 1...4 by quartile of the days that had reviews.
            var level: Int
            var id: Date { date }
        }

        /// From the first day of the first week to today.
        var days: [Day]
        var activeDays: Int
        var total: Int
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
    /// Biggest first.
    var opportunities: [Opportunity] = []
    /// How far library analysis has got, 0...100. Nil once it's complete.
    var scanPercent: Int?
    var computedAt: Date
    // Optional, so a snapshot cached before them still decodes. Fields cached by older builds that are
    // gone now (health, cumulative, weekly, timeline, forecast, insights, and `activity`, which measured
    // bytes cleared) are ignored when decoding.
    var composition: [Slice]?
    var reviews: Activity?

    var recoverableBytes: Int64 { opportunities.reduce(0) { $0 + $1.bytes } }
    var weeklyChange: WeeklyChange? { DashboardStats.weeklyChange(this: clearedThisWeek, last: clearedLastWeek) }
}

/// Builds a `DashboardSnapshot`. Pure: no PhotoKit, no store, time and calendar passed in.
enum DashboardStats {
    static let activityWeeks = 16

    /// - Parameter reviews: Items reviewed by day (`ProgressStoring.reviewsByDay`), keyed by the day's start.
    static func make(history: [CleanupEntry], scan: LibraryScan?, reviews: [Date: Int] = [:], now: Date,
                     calendar: Calendar = .current) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot(computedAt: now)
        snapshot.totalCleared = history.reduce(0) { $0 + $1.bytes }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        snapshot.clearedThisWeek = history.filter { $0.at > weekAgo && $0.at <= now }.reduce(0) { $0 + $1.bytes }
        snapshot.clearedLastWeek = history.filter { $0.at > twoWeeksAgo && $0.at <= weekAgo }.reduce(0) { $0 + $1.bytes }
        if let scan {
            snapshot.opportunities = opportunities(scan)
            snapshot.scanPercent = scan.scanPercent
        }
        snapshot.reviews = activity(reviews, now: now, calendar: calendar)
        if let profile = scan?.profile, profile.totalBytes > 0 {
            snapshot.composition = composition(profile)
        }
        return snapshot
    }

    /// Biggest first; equal sizes keep `LibraryProfile.Kind`'s order.
    static func composition(_ profile: LibraryProfile) -> [DashboardSnapshot.Slice] {
        let total = Double(profile.totalBytes)
        guard total > 0 else { return [] }
        let order: [LibraryProfile.Kind: Int] = Dictionary(uniqueKeysWithValues: LibraryProfile.Kind.allCases.enumerated().map { ($1, $0) })
        let slices: [DashboardSnapshot.Slice] = profile.composition.compactMap { kind, bucket in
            bucket.count > 0 ? DashboardSnapshot.Slice(kind: kind, count: bucket.count, bytes: bucket.bytes, share: Double(bucket.bytes) / total) : nil
        }
        return slices.sorted { first, second in
            if first.bytes != second.bytes { return first.bytes > second.bytes }
            return order[first.kind, default: 0] < order[second.kind, default: 0]
        }
    }

    /// The first day the heatmap shows: the start of the week `activityWeeks - 1` weeks before this one.
    static func activityStart(now: Date, calendar: Calendar) -> Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .weekOfYear, value: -(activityWeeks - 1), to: thisWeek) ?? thisWeek
    }

    static func activity(_ reviews: [Date: Int], now: Date, calendar: Calendar) -> DashboardSnapshot.Activity {
        let today = calendar.startOfDay(for: now)
        var dates: [Date] = []
        var day = activityStart(now: now, calendar: calendar)
        while day <= today {
            dates.append(day)
            // Back to the start of the day: where DST starts at midnight, a day begins at 01:00.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        let active = dates.compactMap { reviews[$0] }.filter { $0 > 0 }.sorted()
        let days = dates.map { date in
            let count = reviews[date] ?? 0
            return DashboardSnapshot.Activity.Day(date: date, count: count, level: level(of: count, among: active))
        }
        return DashboardSnapshot.Activity(days: days, activeDays: active.count, total: active.reduce(0, +))
    }

    /// 1...4 by where `count` ranks among `sorted` (the active days' counts, ascending); 0 for none. The
    /// biggest day is always 4, so a lone day of reviews shows dark, not as the lightest step.
    static func level(of count: Int, among sorted: [Int]) -> Int {
        guard count > 0, !sorted.isEmpty else { return 0 }
        // The share of active days at or under this one, rounded up to a quarter, so ties share a level.
        let atOrBelow = sorted.filter { $0 <= count }.count
        return min(4, max(1, (atOrBelow * 4 + sorted.count - 1) / sorted.count))
    }

    /// Nil when neither week cleared anything, so there's no line to show.
    static func weeklyChange(this: Int64, last: Int64) -> DashboardSnapshot.WeeklyChange? {
        guard this > 0 || last > 0 else { return nil }
        return DashboardSnapshot.WeeklyChange(delta: this - last, percent: last > 0 ? Double(this - last) / Double(last) : nil)
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
}
