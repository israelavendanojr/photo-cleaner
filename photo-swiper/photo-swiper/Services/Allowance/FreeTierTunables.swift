import Foundation
import Observation

/// The free tier's limits as the app applies them. Unlocked users skip all of these.
struct FreeTierLimits: Equatable, Sendable {
    var allowance = SwipeAllowance.Tunables.standard
    /// How much a free user's pile holds before they have to delete it, e.g. 1 GB.
    var freeBinBytes: Int64 = 1_000_000_000

    static let standard = FreeTierLimits()

    /// The launch values: the standard ones, except debug builds' `-refillSoon YES` refills every minute.
    static var launch: FreeTierLimits {
        var limits = FreeTierLimits.standard
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "refillSoon") { limits.allowance = .refillSoon }
        #endif
        return limits
    }
}

/// One value Developer mode can tune. Adding one is a case here plus its arms below; the
/// Settings panel lists every case on its own.
enum FreeTierTunable: String, CaseIterable, Identifiable, Sendable {
    case swipeCap
    case refillAmount
    case refillIntervalMinutes
    case freeBinMB

    var id: Self { self }

    var title: String {
        switch self {
        case .swipeCap: "Swipe cap"
        case .refillAmount: "Refill amount"
        case .refillIntervalMinutes: "Refill every"
        case .freeBinMB: "Free bin size"
        }
    }

    /// Shown after the value, e.g. "min".
    var unit: String {
        switch self {
        case .swipeCap, .refillAmount: "swipes"
        case .refillIntervalMinutes: "min"
        case .freeBinMB: "MB"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .swipeCap, .refillAmount: 1...500
        case .refillIntervalMinutes: 1...1440
        case .freeBinMB: 10...10_000
        }
    }

    /// The stepper's step.
    var step: Int {
        switch self {
        case .swipeCap, .refillAmount: 1
        case .refillIntervalMinutes: 5
        case .freeBinMB: 50
        }
    }

    /// Where a saved override lives.
    var defaultsKey: String { "freeTier.\(rawValue)" }

    func value(in limits: FreeTierLimits) -> Int {
        switch self {
        case .swipeCap: limits.allowance.cap
        case .refillAmount: limits.allowance.refillAmount
        case .refillIntervalMinutes: max(1, Int((limits.allowance.refillInterval / 60).rounded()))
        case .freeBinMB: Int(limits.freeBinBytes / 1_000_000)
        }
    }

    func apply(_ value: Int, to limits: inout FreeTierLimits) {
        switch self {
        case .swipeCap: limits.allowance.cap = value
        case .refillAmount: limits.allowance.refillAmount = value
        case .refillIntervalMinutes: limits.allowance.refillInterval = TimeInterval(value) * 60
        case .freeBinMB: limits.freeBinBytes = Int64(value) * 1_000_000
        }
    }
}

/// The one place the free tier's limits come from. `SwipeAllowance` and the pile limit read `limits`.
///
/// Developer mode can override any `FreeTierTunable`; overrides are saved in `UserDefaults` and apply
/// live. With Developer mode off they're kept but ignored, so the app runs on `baseline`.
@Observable
@MainActor
final class FreeTierTunables {
    static let shared = FreeTierTunables(baseline: .launch, defaults: .standard, devMode: .shared)

    /// The hardcoded values, shown beside each field as its default.
    let baseline: FreeTierLimits
    private var overrides: [FreeTierTunable: Int]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let devMode: DevMode?

    /// Without `devMode` nothing is ever overridden; without `defaults` overrides only live in memory.
    init(baseline: FreeTierLimits = .standard, defaults: UserDefaults?, devMode: DevMode?) {
        self.baseline = baseline
        self.defaults = defaults
        self.devMode = devMode
        var saved: [FreeTierTunable: Int] = [:]
        for tunable in FreeTierTunable.allCases {
            if let value = defaults?.object(forKey: tunable.defaultsKey) as? Int {
                saved[tunable] = tunable.range.clamped(value)
            }
        }
        overrides = saved
    }

    /// Fixed values that never change: tests, previews, and mocks given explicit tunables.
    static func fixed(_ limits: FreeTierLimits = .standard) -> FreeTierTunables {
        FreeTierTunables(baseline: limits, defaults: nil, devMode: nil)
    }

    /// Overrides are being applied.
    var appliesOverrides: Bool { devMode?.isEnabled ?? false }

    /// What the app uses right now.
    var limits: FreeTierLimits {
        guard appliesOverrides else { return baseline }
        var limits = baseline
        for (tunable, value) in overrides { tunable.apply(value, to: &limits) }
        return limits
    }

    func value(_ tunable: FreeTierTunable) -> Int { tunable.value(in: limits) }

    func defaultValue(_ tunable: FreeTierTunable) -> Int { tunable.value(in: baseline) }

    /// Clamped to the tunable's range. Setting the default clears the override.
    func set(_ tunable: FreeTierTunable, _ value: Int) {
        let value = tunable.range.clamped(value)
        if value == defaultValue(tunable) {
            overrides[tunable] = nil
            defaults?.removeObject(forKey: tunable.defaultsKey)
        } else {
            overrides[tunable] = value
            defaults?.set(value, forKey: tunable.defaultsKey)
        }
    }

    func resetToDefaults() {
        for tunable in FreeTierTunable.allCases { defaults?.removeObject(forKey: tunable.defaultsKey) }
        overrides = [:]
    }

    /// Some value differs from its default.
    var isCustomized: Bool { !overrides.isEmpty }
}

private extension ClosedRange where Bound == Int {
    func clamped(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

extension Format {
    /// A limit, rounded the way people say it: "1 GB", "1.5 GB", "500 MB".
    static func limit(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            let gb = Double(bytes) / 1_000_000_000
            return gb.formatted(.number.precision(.fractionLength(0...2))) + " GB"
        }
        return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }
}
