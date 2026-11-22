import Foundation
import Observation

/// How the Library's Top Categories behave (JUN-88): how many rows it shows, and how many of them still
/// open the feed while `TierFeature.topCategories` is locked for the plan.
struct TopCategoriesLimits: Equatable, Sendable {
    var count = 3
    /// The first rows stay free while the section is locked; the rest open the paywall.
    var freeRows = 1

    static let standard = TopCategoriesLimits()

    /// Whether tapping the row at `index` focuses the feed (otherwise it opens the paywall). Unlocked,
    /// every row does; locked, only the first `freeRows`. Off, the section isn't shown at all.
    func opensFeed(rowAt index: Int, access: FeatureAccess) -> Bool {
        switch access {
        case .unlocked: true
        case .locked: index < freeRows
        case .off: false
        }
    }
}

/// One value Developer mode can tune for Top Categories. Adding one is a case here plus its arms below;
/// the Admin Tools panel lists every case on its own.
enum TopCategoriesTunable: String, CaseIterable, Identifiable, Sendable, AdminTunable {
    case count
    case freeRows

    var id: Self { self }

    var title: String {
        switch self {
        case .count: "Top categories"
        case .freeRows: "Free while locked"
        }
    }

    /// Shown after the value.
    var unit: String { "rows" }

    var range: ClosedRange<Int> {
        switch self {
        case .count: 1...8
        case .freeRows: 0...8
        }
    }

    var step: Int { 1 }

    /// Where a saved override lives.
    var defaultsKey: String { "topCategories.\(rawValue)" }

    func value(in limits: TopCategoriesLimits) -> Int {
        switch self {
        case .count: limits.count
        case .freeRows: limits.freeRows
        }
    }

    func apply(_ value: Int, to limits: inout TopCategoriesLimits) {
        switch self {
        case .count: limits.count = value
        case .freeRows: limits.freeRows = value
        }
    }
}

/// The one place Top Categories' limits come from. The Library reads `limits`.
///
/// Developer mode can override any `TopCategoriesTunable`; overrides are saved in `UserDefaults` and apply
/// live. With Developer mode off they're kept but ignored, so the app runs on `baseline`.
@Observable
@MainActor
final class TopCategoriesTunables {
    static let shared = TopCategoriesTunables(baseline: .standard, defaults: .standard, devMode: .shared)

    /// The hardcoded values, shown beside each field as its default.
    let baseline: TopCategoriesLimits
    private var overrides: [TopCategoriesTunable: Int]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let devMode: DevMode?

    /// Without `devMode` nothing is ever overridden; without `defaults` overrides only live in memory.
    init(baseline: TopCategoriesLimits = .standard, defaults: UserDefaults?, devMode: DevMode?) {
        self.baseline = baseline
        self.defaults = defaults
        self.devMode = devMode
        var saved: [TopCategoriesTunable: Int] = [:]
        for tunable in TopCategoriesTunable.allCases {
            if let value = defaults?.object(forKey: tunable.defaultsKey) as? Int {
                saved[tunable] = Self.clamped(value, to: tunable.range)
            }
        }
        overrides = saved
    }

    /// Fixed values that never change: tests, previews, and mocks given explicit tunables.
    static func fixed(_ limits: TopCategoriesLimits = .standard) -> TopCategoriesTunables {
        TopCategoriesTunables(baseline: limits, defaults: nil, devMode: nil)
    }

    /// Overrides are being applied.
    var appliesOverrides: Bool { devMode?.isEnabled ?? false }

    /// What the app uses right now.
    var limits: TopCategoriesLimits {
        guard appliesOverrides else { return baseline }
        var limits = baseline
        for (tunable, value) in overrides { tunable.apply(value, to: &limits) }
        return limits
    }

    func value(_ tunable: TopCategoriesTunable) -> Int { tunable.value(in: limits) }

    func defaultValue(_ tunable: TopCategoriesTunable) -> Int { tunable.value(in: baseline) }

    /// Clamped to the tunable's range. Setting the default clears the override.
    func set(_ tunable: TopCategoriesTunable, _ value: Int) {
        let value = Self.clamped(value, to: tunable.range)
        if value == defaultValue(tunable) {
            overrides[tunable] = nil
            defaults?.removeObject(forKey: tunable.defaultsKey)
        } else {
            overrides[tunable] = value
            defaults?.set(value, forKey: tunable.defaultsKey)
        }
    }

    func resetToDefaults() {
        for tunable in TopCategoriesTunable.allCases { defaults?.removeObject(forKey: tunable.defaultsKey) }
        overrides = [:]
    }

    /// Some value differs from its default.
    var isCustomized: Bool { !overrides.isEmpty }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
