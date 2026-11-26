import Foundation
import Observation

/// A feature each plan gets off, locked or unlocked (`FeatureAccess`). Adding one is a case here plus
/// its arms below and its baseline in `standard`, and in `FeedCard.feature` for a card bundle; the
/// Settings panel lists every case on its own.
enum TierFeature: String, CaseIterable, Identifiable, Sendable {
    case similarShots
    case duplicates
    case screenshotBatches
    /// Trim handles in the full-screen video (JUN-7). Off leaves a plain seek bar.
    case videoTrimmer
    /// The compression button in the full-screen video (JUN-50). Off hides it.
    case videoCompression
    /// Flatten and Change & Flatten in the full-screen photo of a Live Photo (JUN-79, JUN-106). Off hides them.
    case livePhotoFlatten
    /// The feed's filter pill and its menu (JUN-87).
    case feedFilters
    /// The feed's sort pill and its menu (JUN-125). Off hides it; locked opens the paywall for any sort but Recommended.
    case feedSort
    /// The Library's Top Categories rows (JUN-88).
    case topCategories
    /// The Share button on single photo and video cards (JUN-8). Off hides it; locked opens the paywall.
    case sharing

    var id: Self { self }

    var title: String {
        switch self {
        case .similarShots: "Similar shots"
        case .duplicates: "Duplicates"
        case .screenshotBatches: "Screenshot batches"
        case .videoTrimmer: "Video Trimmer"
        case .videoCompression: "Video Compression"
        case .livePhotoFlatten: "Live Photo flatten"
        case .feedFilters: "Feed filters"
        case .feedSort: "Feed sort"
        case .topCategories: "Top categories"
        case .sharing: "Share"
        }
    }

    var icon: String {
        switch self {
        case .similarShots: "square.stack"
        case .duplicates: "doc.on.doc"
        case .screenshotBatches: "iphone"
        case .videoTrimmer: "scissors"
        case .videoCompression: "arrow.down.right.and.arrow.up.left"
        case .livePhotoFlatten: "livephoto"
        case .feedFilters: "line.3.horizontal.decrease"
        case .feedSort: "arrow.up.arrow.down"
        case .topCategories: "chart.bar"
        case .sharing: "square.and.arrow.up"
        }
    }

    /// Where a saved override for one plan lives.
    func defaultsKey(_ plan: Plan) -> String { "feature.\(rawValue).\(plan.rawValue)" }

    /// Where the one override for both plans lived before JUN-87. Read once, migrated, then removed.
    var legacyDefaultsKey: String { "feature.\(rawValue)" }
}

/// The two plans a feature can be set for.
enum Plan: String, CaseIterable, Identifiable, Sendable {
    case free
    case paid

    init(isUnlocked: Bool) { self = isUnlocked ? .paid : .free }

    var id: Self { self }

    var title: String {
        switch self {
        case .free: "Free"
        case .paid: "Paid"
        }
    }
}

/// What one plan gets of a `TierFeature`.
enum FeatureAccess: String, CaseIterable, Identifiable, Sendable {
    /// The feature isn't there at all.
    case off
    /// The feature shows and can be tried, but its commit or apply action opens the paywall instead
    /// (`FeedViewModel.isLocked`, `lockedPrompt`).
    case locked
    /// The feature works.
    case unlocked

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .locked: "Locked"
        case .unlocked: "Unlocked"
        }
    }

    /// Shown at all: locked features show, only their commit is held back.
    var isVisible: Bool { self != .off }
}

/// A feature's access on each plan.
struct PlanAccess: Equatable, Sendable {
    var free: FeatureAccess
    var paid: FeatureAccess

    /// Works for everyone.
    static let everyone = PlanAccess(free: .unlocked, paid: .unlocked)

    subscript(plan: Plan) -> FeatureAccess {
        get { plan == .free ? free : paid }
        set { if plan == .free { free = newValue } else { paid = newValue } }
    }

    func access(isUnlocked: Bool) -> FeatureAccess { self[Plan(isUnlocked: isUnlocked)] }
}

extension [TierFeature: PlanAccess] {
    /// The hardcoded defaults. The filter and sort pills and Top Categories are a reason to unlock, so free users
    /// see them locked; everything older works for everyone, as it did before JUN-87.
    static var standard: Self {
        Dictionary(uniqueKeysWithValues: TierFeature.allCases.map { feature in
            switch feature {
            case .feedFilters, .feedSort, .topCategories: (feature, PlanAccess(free: .locked, paid: .unlocked))
            case .similarShots, .duplicates, .screenshotBatches, .videoTrimmer, .videoCompression, .livePhotoFlatten, .sharing:
                (feature, .everyone)
            }
        })
    }
}

/// The one place feature access comes from. The feed splits bundles that are off for a user into
/// single cards (see `FeedCard.unbundled(unless:)`); a locked bundle stays a bundle.
///
/// Developer mode can override each plan of each feature; overrides are saved in `UserDefaults` and apply
/// to the next page. With Developer mode off they're kept but ignored, so the app runs on `baseline`.
@Observable
@MainActor
final class FeatureAvailabilityTunables {
    static let shared = FeatureAvailabilityTunables(baseline: .standard, defaults: .standard, devMode: .shared)

    /// The hardcoded values, shown beside each plan's picker as its default.
    let baseline: [TierFeature: PlanAccess]
    private var overrides: [TierFeature: [Plan: FeatureAccess]]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let devMode: DevMode?

    /// Without `devMode` nothing is ever overridden; without `defaults` overrides only live in memory.
    /// A pre-JUN-87 override is migrated to its two plans here, so a tester's setup survives the update.
    init(baseline: [TierFeature: PlanAccess] = .standard, defaults: UserDefaults?, devMode: DevMode?) {
        self.baseline = baseline
        self.defaults = defaults
        self.devMode = devMode
        var saved: [TierFeature: [Plan: FeatureAccess]] = [:]
        for feature in TierFeature.allCases {
            let fallback = baseline[feature] ?? .everyone
            if let raw = defaults?.string(forKey: feature.legacyDefaultsKey) {
                defaults?.removeObject(forKey: feature.legacyDefaultsKey)
                if let legacy = LegacyAvailability(rawValue: raw) {
                    for plan in Plan.allCases where defaults?.string(forKey: feature.defaultsKey(plan)) == nil
                        && legacy.access[plan] != fallback[plan] {
                        defaults?.set(legacy.access[plan].rawValue, forKey: feature.defaultsKey(plan))
                    }
                }
            }
            for plan in Plan.allCases {
                if let raw = defaults?.string(forKey: feature.defaultsKey(plan)), let value = FeatureAccess(rawValue: raw) {
                    saved[feature, default: [:]][plan] = value
                }
            }
        }
        overrides = saved
    }

    /// Fixed values that never change: tests, previews, and mocks given explicit tunables.
    static func fixed(_ baseline: [TierFeature: PlanAccess] = .standard) -> FeatureAvailabilityTunables {
        FeatureAvailabilityTunables(baseline: baseline, defaults: nil, devMode: nil)
    }

    /// Overrides are being applied.
    var appliesOverrides: Bool { devMode?.isEnabled ?? false }

    /// What each plan gets right now.
    func planAccess(_ feature: TierFeature) -> PlanAccess {
        var access = defaultPlanAccess(feature)
        if appliesOverrides {
            for (plan, value) in overrides[feature] ?? [:] { access[plan] = value }
        }
        return access
    }

    func defaultPlanAccess(_ feature: TierFeature) -> PlanAccess { baseline[feature] ?? .everyone }

    /// What a free or unlocked user gets of `feature` right now.
    func access(_ feature: TierFeature, isUnlocked: Bool) -> FeatureAccess {
        planAccess(feature).access(isUnlocked: isUnlocked)
    }

    /// The features a free or unlocked user can see right now, locked or not.
    func visible(isUnlocked: Bool) -> Set<TierFeature> {
        Set(TierFeature.allCases.filter { access($0, isUnlocked: isUnlocked).isVisible })
    }

    /// Setting the default clears the override.
    func set(_ feature: TierFeature, on plan: Plan, _ value: FeatureAccess) {
        if value == defaultPlanAccess(feature)[plan] {
            overrides[feature]?[plan] = nil
            if overrides[feature]?.isEmpty == true { overrides[feature] = nil }
            defaults?.removeObject(forKey: feature.defaultsKey(plan))
        } else {
            overrides[feature, default: [:]][plan] = value
            defaults?.set(value.rawValue, forKey: feature.defaultsKey(plan))
        }
    }

    func resetToDefaults() {
        for feature in TierFeature.allCases {
            for plan in Plan.allCases { defaults?.removeObject(forKey: feature.defaultsKey(plan)) }
        }
        overrides = [:]
    }

    /// Some feature differs from its default.
    var isCustomized: Bool { !overrides.isEmpty }
}

/// The single setting each feature had before JUN-87, kept only to migrate saved overrides.
enum LegacyAvailability: String, CaseIterable, Sendable {
    case freeOnly
    case paidOnly
    case universal
    case off

    /// The same rule as two plans: what was allowed is unlocked, what wasn't is off.
    var access: PlanAccess {
        switch self {
        case .universal: PlanAccess(free: .unlocked, paid: .unlocked)
        case .freeOnly: PlanAccess(free: .unlocked, paid: .off)
        case .paidOnly: PlanAccess(free: .off, paid: .unlocked)
        case .off: PlanAccess(free: .off, paid: .off)
        }
    }
}
