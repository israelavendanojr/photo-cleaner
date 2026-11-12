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

    /// Cleanups by day over the last `DashboardStats.activityWeeks` weeks, and the streak.
    struct Activity: Equatable, Codable, Sendable {
        struct Day: Equatable, Codable, Sendable, Identifiable {
            var date: Date
            var bytes: Int64
            /// 0 for nothing cleared, then 1...4 by quartile of the days that had something.
            var level: Int
            var id: Date { date }
        }

        /// From the first day of the first week to today.
        var days: [Day]
        var activeDays: Int
        /// Calendar weeks in a row with a cleanup, ending this week, or last week if this one has none yet.
        var streakWeeks: Int
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
    // gone now (health, cumulative, weekly, timeline, forecast, insights) are ignored when decoding.
    var composition: [Slice]?
    var activity: Activity?

    var recoverableBytes: Int64 { opportunities.reduce(0) { $0 + $1.bytes } }
}

/// Builds a `DashboardSnapshot`. Pure: no PhotoKit, no store, time and calendar passed in.
enum DashboardStats {
    static let activityWeeks = 16

    static func make(history: [CleanupEntry], scan: LibraryScan?, now: Date, calendar: Calendar = .current) -> DashboardSnapshot {
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
        snapshot.activity = activity(history, now: now, calendar: calendar)
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

    static func activity(_ history: [CleanupEntry], now: Date, calendar: Calendar) -> DashboardSnapshot.Activity {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -(activityWeeks - 1), to: thisWeek) ?? thisWeek
        let byDay = Dictionary(grouping: history) { calendar.startOfDay(for: $0.at) }.mapValues { $0.reduce(0) { $0 + $1.bytes } }

        var dates: [Date] = []
        var day = start
        while day <= today {
            dates.append(day)
            // Back to the start of the day: where DST starts at midnight, a day begins at 01:00.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        let active = dates.compactMap { byDay[$0] }.filter { $0 > 0 }.sorted()
        let days = dates.map { date in
            let bytes = byDay[date] ?? 0
            return DashboardSnapshot.Activity.Day(date: date, bytes: bytes, level: level(of: bytes, among: active))
        }

        let weeks = Set(history.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.at)?.start })
        var week = weeks.contains(thisWeek) ? thisWeek : previousWeek(thisWeek, calendar: calendar)
        var streak = 0
        while let current = week, weeks.contains(current) {
            streak += 1
            week = previousWeek(current, calendar: calendar)
        }
        return DashboardSnapshot.Activity(days: days, activeDays: active.count, streakWeeks: streak)
    }

    /// The start of the week before the one starting at `week`. Stepping back from just before it, not by
    /// subtracting a week, so a week that starts at 01:00 (DST at midnight) still lands on a week's start.
    private static func previousWeek(_ week: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: week.addingTimeInterval(-1))?.start
    }

    /// 1...4 by where `bytes` ranks among `sorted` (the active days' bytes, ascending); 0 for none. The
    /// biggest day is always 4, so a lone cleanup day shows dark, not as the lightest step.
    static func level(of bytes: Int64, among sorted: [Int64]) -> Int {
        guard bytes > 0, !sorted.isEmpty else { return 0 }
        // The share of active days at or under this one, rounded up to a quarter, so ties share a level.
        let atOrBelow = sorted.filter { $0 <= bytes }.count
        return min(4, max(1, (atOrBelow * 4 + sorted.count - 1) / sorted.count))
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
