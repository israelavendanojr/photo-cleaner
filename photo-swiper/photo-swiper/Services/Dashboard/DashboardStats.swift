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

    /// The library's size at the end of a month: everything taken up to then that's still in it.
    struct MonthPoint: Equatable, Codable, Sendable, Identifiable {
        /// The month's first day.
        var date: Date
        var total: Int64
        var id: Date { date }
    }

    /// When the device fills at the recent pace of new photos and videos.
    struct Forecast: Equatable, Codable, Sendable {
        var total: Int64
        var available: Int64
        /// The photo library's share of what's used.
        var libraryBytes: Int64
        /// New photos and videos a day, over the last `LibraryProfile.recentDays`.
        var bytesPerDay: Double
        /// Nil when nothing new was added lately.
        var daysUntilFull: Double? { bytesPerDay > 0 ? Double(available) / bytesPerDay : nil }
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

    struct YearCount: Equatable, Codable, Sendable, Identifiable {
        var year: Int
        var count: Int
        var id: Int { year }
    }

    /// Facts about the library, from when things were taken.
    struct Insights: Equatable, Codable, Sendable {
        /// The month with the most items taken, and how many.
        var busiestMonth: Date?
        var busiestMonthCount: Int
        /// The most recent years, oldest first, at most `DashboardStats.insightYears`.
        var perYear: [YearCount]
        var oldestUnreviewedYear: Int?
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
    // Added in PR 2 of JUN-9. Optional, so a snapshot cached before them still decodes.
    var timeline: [MonthPoint]?
    var forecast: Forecast?
    var composition: [Slice]?
    var activity: Activity?
    var insights: Insights?

    var recoverableBytes: Int64 { opportunities.reduce(0) { $0 + $1.bytes } }
}

/// Builds a `DashboardSnapshot`. Pure: no PhotoKit, no store, time and calendar passed in.
enum DashboardStats {
    static let maxWeeks = 26
    static let timelineMonths = 60
    static let activityWeeks = 16
    static let insightYears = 8

    static func make(
        history: [CleanupEntry], scan: LibraryScan?, reviewedFraction: Double, storage: DeviceStorage? = nil,
        now: Date, calendar: Calendar = .current
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
        snapshot.activity = activity(history, now: now, calendar: calendar)
        if let profile = scan?.profile, profile.totalBytes > 0 {
            snapshot.timeline = timeline(profile, now: now, calendar: calendar)
            snapshot.composition = composition(profile)
            snapshot.insights = insights(profile, calendar: calendar)
            if let storage {
                snapshot.forecast = DashboardSnapshot.Forecast(total: storage.total, available: storage.available, libraryBytes: profile.totalBytes,
                                                               bytesPerDay: Double(profile.addedRecently) / Double(LibraryProfile.recentDays))
            }
        }
        return snapshot
    }

    /// The running size by month up to this one, the last `timelineMonths` of it; earlier months are
    /// the first point's starting size.
    static func timeline(_ profile: LibraryProfile, now: Date, calendar: Calendar) -> [DashboardSnapshot.MonthPoint] {
        let months = profile.monthly.keys.filter { $0 <= now }.sorted()
        let shown = months.suffix(timelineMonths)
        var total = months.prefix(months.count - shown.count).reduce(Int64(0)) { $0 + (profile.monthly[$1]?.bytes ?? 0) }
        return shown.map { month in
            total += profile.monthly[month]?.bytes ?? 0
            return DashboardSnapshot.MonthPoint(date: month, total: total)
        }
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
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let active = dates.compactMap { byDay[$0] }.filter { $0 > 0 }.sorted()
        let days = dates.map { date in
            let bytes = byDay[date] ?? 0
            return DashboardSnapshot.Activity.Day(date: date, bytes: bytes, level: level(of: bytes, among: active))
        }

        let weeks = Set(history.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.at)?.start })
        var week = weeks.contains(thisWeek) ? thisWeek : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        var streak = 0
        while let current = week, weeks.contains(current) {
            streak += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: current)
        }
        return DashboardSnapshot.Activity(days: days, activeDays: active.count, streakWeeks: streak)
    }

    /// 1...4 by which quartile of `sorted` (the active days' bytes, ascending) `bytes` falls in; 0 for none.
    static func level(of bytes: Int64, among sorted: [Int64]) -> Int {
        guard bytes > 0, !sorted.isEmpty else { return 0 }
        let below = sorted.filter { $0 < bytes }.count
        return min(4, 1 + below * 4 / sorted.count)
    }

    static func insights(_ profile: LibraryProfile, calendar: Calendar) -> DashboardSnapshot.Insights {
        // The most items; a tie goes to the more recent month.
        let busiest = profile.monthly.max { first, second in
            first.value.count != second.value.count ? first.value.count < second.value.count : first.key < second.key
        }
        var years: [Int: Int] = [:]
        for (month, bucket) in profile.monthly { years[calendar.component(.year, from: month), default: 0] += bucket.count }
        let perYear = years.keys.sorted().suffix(insightYears).map { DashboardSnapshot.YearCount(year: $0, count: years[$0] ?? 0) }
        return DashboardSnapshot.Insights(
            busiestMonth: busiest?.key, busiestMonthCount: busiest?.value.count ?? 0, perYear: Array(perYear),
            oldestUnreviewedYear: profile.oldestUnreviewed.map { calendar.component(.year, from: $0) }
        )
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
