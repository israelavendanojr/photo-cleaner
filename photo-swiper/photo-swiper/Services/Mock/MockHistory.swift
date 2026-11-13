import Foundation

#if DEBUG
/// About ten weeks of made-up cleanups, for previews, `-mockHistory YES` and screenshots. The same on every run.
enum MockHistory {
    static func entries(now: Date, weeks: Int = 10) -> [CleanupEntry] {
        var rng = SeededGenerator(seed: 9)
        var entries: [CleanupEntry] = []
        for day in stride(from: weeks * 7, through: 0, by: -1) {
            // Most days nothing; some days one or two deletes from the pile.
            guard rng.unit() < 0.32, let at = Calendar.current.date(byAdding: .day, value: -day, to: now) else { continue }
            let category = CleanupCategory.allCases[Int(rng.unit() * Double(CleanupCategory.allCases.count))]
            let count = 1 + Int(rng.unit() * 24)
            let each: Double = category == .video ? 140_000_000 : 3_200_000
            entries.append(CleanupEntry(at: at, category: category, count: count, bytes: Int64(Double(count) * each * (0.5 + rng.unit()))))
        }
        return entries
    }

    /// When about ten weeks of made-up reviews happened: most days a few, some days many, some none.
    static func reviews(now: Date, weeks: Int = 10) -> [Date] {
        var rng = SeededGenerator(seed: 17)
        var reviews: [Date] = []
        for day in stride(from: weeks * 7, through: 1, by: -1) {
            guard rng.unit() < 0.55, let at = Calendar.current.date(byAdding: .day, value: -day, to: now) else { continue }
            reviews += Array(repeating: at, count: 1 + Int(rng.unit() * rng.unit() * 120))
        }
        return reviews
    }

    static func reviewsByDay(now: Date) -> [Date: Int] {
        Dictionary(grouping: reviews(now: now)) { Calendar.current.startOfDay(for: $0) }.mapValues(\.count)
    }
}

extension DashboardSnapshot {
    /// A populated dashboard for previews.
    static var preview: DashboardSnapshot {
        DashboardStats.make(history: MockHistory.entries(now: .now), scan: MockFeedBuilder.scan,
                            reviews: MockHistory.reviewsByDay(now: .now), now: .now)
    }
}
#endif
