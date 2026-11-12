import Foundation

extension DashboardSnapshot {
    /// Stand-in shapes for the first load, shown redacted, never real numbers.
    static func placeholder(now: Date = .now) -> DashboardSnapshot {
        DashboardSnapshot(
            totalCleared: 1_000_000_000,
            computedAt: now,
            composition: LibraryProfile.Kind.allCases.map { Slice(kind: $0, count: 1_000, bytes: 10_000_000_000, share: 0.25) },
            chips: [FocusTarget.category(.duplicate), .category(.video), .category(.screenshot)].map {
                Chip(focus: $0, count: 100, bytes: 1_000_000_000, thumbnails: [])
            },
            defaultChip: .category(.duplicate)
        )
    }
}
