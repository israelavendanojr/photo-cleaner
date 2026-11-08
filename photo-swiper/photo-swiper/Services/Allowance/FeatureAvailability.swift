import Foundation
import Observation

/// A feature that can be limited to free or unlocked users. Adding one is a case here plus its arms
/// below and in `FeedCard.feature`; the Settings panel lists every case on its own.
enum TierFeature: String, CaseIterable, Identifiable, Sendable {
    case similarShots
    case duplicates
    case screenshotBatches

    var id: Self { self }

    var title: String {
        switch self {
        case .similarShots: "Similar shots"
        case .duplicates: "Duplicates"
        case .screenshotBatches: "Screenshot batches"
        }
    }

    var icon: String {
        switch self {
        case .similarShots: "square.stack"
        case .duplicates: "doc.on.doc"
        case .screenshotBatches: "iphone"
        }
    }

    /// Where a saved override lives.
    var defaultsKey: String { "feature.\(rawValue)" }
}

/// Who gets a `TierFeature`.
enum FeatureAvailability: String, CaseIterable, Identifiable, Sendable {
    case freeOnly
    case paidOnly
    case universal

    var id: Self { self }

    var title: String {
        switch self {
        case .freeOnly: "Free only"
        case .paidOnly: "Paid only"
        case .universal: "Universal"
        }
    }

    func allows(isUnlocked: Bool) -> Bool {
        switch self {
        case .freeOnly: !isUnlocked
        case .paidOnly: isUnlocked
        case .universal: true
        }
    }
}

extension [TierFeature: FeatureAvailability] {
    /// Every feature for everyone.
    static var standard: Self { Dictionary(uniqueKeysWithValues: TierFeature.allCases.map { ($0, .universal) }) }
}

/// The one place feature availability comes from. The feed splits bundles a user doesn't get into
/// single cards (see `FeedCard.unbundled(unless:)`).
///
/// Developer mode can override any feature; overrides are saved in `UserDefaults` and apply to the
/// next page. With Developer mode off they're kept but ignored, so the app runs on `baseline`.
@Observable
@MainActor
final class FeatureAvailabilityTunables {
    static let shared = FeatureAvailabilityTunables(baseline: .standard, defaults: .standard, devMode: .shared)

    /// The hardcoded values, shown beside each feature as its default.
    let baseline: [TierFeature: FeatureAvailability]
    private var overrides: [TierFeature: FeatureAvailability]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let devMode: DevMode?

    /// Without `devMode` nothing is ever overridden; without `defaults` overrides only live in memory.
    init(baseline: [TierFeature: FeatureAvailability] = .standard, defaults: UserDefaults?, devMode: DevMode?) {
        self.baseline = baseline
        self.defaults = defaults
        self.devMode = devMode
        var saved: [TierFeature: FeatureAvailability] = [:]
        for feature in TierFeature.allCases {
            if let raw = defaults?.string(forKey: feature.defaultsKey), let value = FeatureAvailability(rawValue: raw) {
                saved[feature] = value
            }
        }
        overrides = saved
    }

    /// Fixed values that never change: tests, previews, and mocks given explicit tunables.
    static func fixed(_ baseline: [TierFeature: FeatureAvailability] = .standard) -> FeatureAvailabilityTunables {
        FeatureAvailabilityTunables(baseline: baseline, defaults: nil, devMode: nil)
    }

    /// Overrides are being applied.
    var appliesOverrides: Bool { devMode?.isEnabled ?? false }

    /// What the app uses right now.
    func availability(_ feature: TierFeature) -> FeatureAvailability {
        (appliesOverrides ? overrides[feature] : nil) ?? defaultAvailability(feature)
    }

    func defaultAvailability(_ feature: TierFeature) -> FeatureAvailability { baseline[feature] ?? .universal }

    /// The features a free or unlocked user gets right now.
    func enabled(isUnlocked: Bool) -> Set<TierFeature> {
        Set(TierFeature.allCases.filter { availability($0).allows(isUnlocked: isUnlocked) })
    }

    /// Setting the default clears the override.
    func set(_ feature: TierFeature, _ value: FeatureAvailability) {
        if value == defaultAvailability(feature) {
            overrides[feature] = nil
            defaults?.removeObject(forKey: feature.defaultsKey)
        } else {
            overrides[feature] = value
            defaults?.set(value.rawValue, forKey: feature.defaultsKey)
        }
    }

    func resetToDefaults() {
        for feature in TierFeature.allCases { defaults?.removeObject(forKey: feature.defaultsKey) }
        overrides = [:]
    }

    /// Some feature differs from its default.
    var isCustomized: Bool { !overrides.isEmpty }
}
