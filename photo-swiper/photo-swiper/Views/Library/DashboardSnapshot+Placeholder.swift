import Foundation

extension DashboardSnapshot {
    /// Stand-in shapes for the first load, shown redacted: rows and a rising line, never real numbers.
    static func placeholder(now: Date = .now) -> DashboardSnapshot {
        let days = (0...6).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: now) }
        return DashboardSnapshot(
            totalCleared: 1_000_000_000,
            cumulative: days.enumerated().map { DayPoint(date: $1, total: Int64($0 + 1) * 150_000_000) },
            weekly: [WeekPoint(date: now, bytes: 1_000_000_000)],
            opportunities: [
                Opportunity(category: .video, count: 10, bytes: 3_000_000_000),
                Opportunity(category: .duplicate, count: 100, bytes: 1_000_000_000),
                Opportunity(category: .screenshot, count: 100, bytes: 500_000_000),
            ],
            health: 0.5,
            computedAt: now,
            timeline: (0...5).compactMap { Calendar.current.date(byAdding: .month, value: $0 - 5, to: now) }
                .enumerated().map { MonthPoint(date: $1, total: Int64($0 + 4) * 5_000_000_000) },
            composition: LibraryProfile.Kind.allCases.map { Slice(kind: $0, count: 1_000, bytes: 10_000_000_000, share: 0.25) },
            insights: Insights(busiestMonth: now, busiestMonthCount: 1_000,
                               perYear: (0..<4).map { YearCount(year: 2022 + $0, count: 2_000) }, oldestUnreviewedYear: 2020)
        )
    }
}
