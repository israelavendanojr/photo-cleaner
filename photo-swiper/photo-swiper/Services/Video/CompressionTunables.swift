import Foundation
import Observation

/// One compression setting Developer mode can tune (JUN-50). Adding one is a case here plus its arms
/// below; the Admin Tools panel lists every case on its own.
enum CompressionTunable: String, CaseIterable, Identifiable, Sendable, AdminTunable {
    case lightBitratePercent
    case balancedLongEdge
    case balancedKbps
    case maxLongEdge
    case maxKbps
    case audioKbps
    case alreadySmallPercent

    var id: Self { self }

    var title: String {
        switch self {
        case .lightBitratePercent: "Light bitrate"
        case .balancedLongEdge: "Balanced long edge"
        case .balancedKbps: "Balanced bitrate"
        case .maxLongEdge: "Max long edge"
        case .maxKbps: "Max bitrate"
        case .audioKbps: "Audio bitrate"
        case .alreadySmallPercent: "Already small under"
        }
    }

    var unit: String {
        switch self {
        case .lightBitratePercent: "% of source"
        case .balancedLongEdge, .maxLongEdge: "px"
        case .balancedKbps, .maxKbps, .audioKbps: "kbps"
        case .alreadySmallPercent: "% saved"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .lightBitratePercent: 10...100
        case .balancedLongEdge, .maxLongEdge: 480...3840
        case .balancedKbps, .maxKbps: 500...50_000
        case .audioKbps: 32...320
        case .alreadySmallPercent: 0...50
        }
    }

    var step: Int {
        switch self {
        case .lightBitratePercent, .alreadySmallPercent: 5
        case .balancedLongEdge, .maxLongEdge: 80
        case .balancedKbps, .maxKbps: 250
        case .audioKbps: 16
        }
    }

    /// Where a saved override lives.
    var defaultsKey: String { "compression.\(rawValue)" }

    func value(in levels: CompressionLevels) -> Int {
        switch self {
        case .lightBitratePercent: Self.percent(levels.light.videoBitrate)
        case .balancedLongEdge: levels.balanced.maxLongEdge ?? range.upperBound
        case .balancedKbps: Self.kbps(levels.balanced.videoBitrate)
        case .maxLongEdge: levels.max.maxLongEdge ?? range.upperBound
        case .maxKbps: Self.kbps(levels.max.videoBitrate)
        case .audioKbps: levels.audioBitrate / 1000
        case .alreadySmallPercent: Int((levels.alreadySmallFraction * 100).rounded())
        }
    }

    func apply(_ value: Int, to levels: inout CompressionLevels) {
        switch self {
        case .lightBitratePercent: levels.light.videoBitrate = .fractionOfSource(Double(value) / 100)
        case .balancedLongEdge: levels.balanced.maxLongEdge = value
        case .balancedKbps: levels.balanced.videoBitrate = .fixed(value * 1000)
        case .maxLongEdge: levels.max.maxLongEdge = value
        case .maxKbps: levels.max.videoBitrate = .fixed(value * 1000)
        case .audioKbps: levels.audioBitrate = value * 1000
        case .alreadySmallPercent: levels.alreadySmallFraction = Double(value) / 100
        }
    }

    private static func percent(_ bitrate: CompressionLevels.Bitrate) -> Int {
        if case .fractionOfSource(let fraction) = bitrate { Int((fraction * 100).rounded()) } else { 100 }
    }

    private static func kbps(_ bitrate: CompressionLevels.Bitrate) -> Int {
        if case .fixed(let bits) = bitrate { bits / 1000 } else { 0 }
    }
}

/// The one place the compression levels' settings come from: the viewer's estimates and previews and
/// the bin's exports all read `levels`.
///
/// Developer mode can override any `CompressionTunable`; overrides are saved in `UserDefaults` and apply
/// live. With Developer mode off they're kept but ignored, so the app runs on `baseline`.
@Observable
@MainActor
final class CompressionTunables {
    static let shared = CompressionTunables(baseline: .standard, defaults: .standard, devMode: .shared)

    /// The hardcoded values, shown beside each field as its default.
    let baseline: CompressionLevels
    private var overrides: [CompressionTunable: Int]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let devMode: DevMode?

    /// Without `devMode` nothing is ever overridden; without `defaults` overrides only live in memory.
    init(baseline: CompressionLevels = .standard, defaults: UserDefaults?, devMode: DevMode?) {
        self.baseline = baseline
        self.defaults = defaults
        self.devMode = devMode
        var saved: [CompressionTunable: Int] = [:]
        for tunable in CompressionTunable.allCases {
            if let value = defaults?.object(forKey: tunable.defaultsKey) as? Int {
                saved[tunable] = min(max(value, tunable.range.lowerBound), tunable.range.upperBound)
            }
        }
        overrides = saved
    }

    /// Fixed values that never change: tests, previews, and mocks given explicit tunables.
    static func fixed(_ levels: CompressionLevels = .standard) -> CompressionTunables {
        CompressionTunables(baseline: levels, defaults: nil, devMode: nil)
    }

    /// Overrides are being applied.
    var appliesOverrides: Bool { devMode?.isEnabled ?? false }

    /// What the app uses right now.
    var levels: CompressionLevels {
        guard appliesOverrides else { return baseline }
        var levels = baseline
        for (tunable, value) in overrides { tunable.apply(value, to: &levels) }
        return levels
    }

    func value(_ tunable: CompressionTunable) -> Int { tunable.value(in: levels) }

    func defaultValue(_ tunable: CompressionTunable) -> Int { tunable.value(in: baseline) }

    /// Clamped to the tunable's range. Setting the default clears the override.
    func set(_ tunable: CompressionTunable, _ value: Int) {
        let value = min(max(value, tunable.range.lowerBound), tunable.range.upperBound)
        if value == defaultValue(tunable) {
            overrides[tunable] = nil
            defaults?.removeObject(forKey: tunable.defaultsKey)
        } else {
            overrides[tunable] = value
            defaults?.set(value, forKey: tunable.defaultsKey)
        }
    }

    func resetToDefaults() {
        for tunable in CompressionTunable.allCases { defaults?.removeObject(forKey: tunable.defaultsKey) }
        overrides = [:]
    }

    /// Some value differs from its default.
    var isCustomized: Bool { !overrides.isEmpty }
}
