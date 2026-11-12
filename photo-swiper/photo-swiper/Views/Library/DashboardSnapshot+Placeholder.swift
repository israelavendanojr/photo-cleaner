import Foundation

extension DashboardSnapshot {
    /// Stand-in shapes for the first load, shown redacted, never real numbers.
    static func placeholder(now: Date = .now) -> DashboardSnapshot {
        DashboardSnapshot(
            totalCleared: 1_000_000_000,
            opportunities: [
                Opportunity(category: .video, count: 10, bytes: 3_000_000_000),
                Opportunity(category: .duplicate, count: 100, bytes: 1_000_000_000),
                Opportunity(category: .screenshot, count: 100, bytes: 500_000_000),
            ],
            computedAt: now,
            composition: LibraryProfile.Kind.allCases.map { Slice(kind: $0, count: 1_000, bytes: 10_000_000_000, share: 0.25) }
        )
    }
}
