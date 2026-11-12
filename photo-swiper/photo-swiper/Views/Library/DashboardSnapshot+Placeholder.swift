import Foundation

extension DashboardSnapshot {
    /// Stand-in shapes for the first load, shown redacted, never real numbers.
    static func placeholder(now: Date = .now) -> DashboardSnapshot {
        DashboardSnapshot(
            totalCleared: 1_000_000_000,
            computedAt: now,
            rows: [FocusTarget.category(.duplicate), .category(.video), .category(.screenshot)].map {
                Row(focus: $0, count: 100, bytes: 1_000_000_000)
            }
        )
    }
}
