import Foundation
import Observation
import StoreKit

/// Where this build was installed from. Decides whether Developer mode can exist at all.
enum DistributionEnvironment: Sendable, Equatable {
    /// A debug build, from Xcode.
    case debug
    /// A release build run from Xcode.
    case xcode
    /// TestFlight (the App Store's sandbox).
    case testFlight
    /// The App Store, or anything that couldn't be determined.
    case production

    var allowsDevMode: Bool { self != .production }

    /// What a build assumes before `resolve()` answers: debug builds know at compile time,
    /// everything else starts as production.
    static var assumed: DistributionEnvironment {
        #if DEBUG
        .debug
        #else
        .production
        #endif
    }

    /// Asks `AppTransaction` where the app came from. Unverified, failed, or unknown answers are production.
    static func resolve() async -> DistributionEnvironment {
        #if DEBUG
        return .debug
        #else
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result else {
            return .production
        }
        return from(transaction.environment)
        #endif
    }

    static func from(_ environment: AppStore.Environment) -> DistributionEnvironment {
        switch environment {
        case .xcode: .xcode
        case .sandbox: .testFlight
        default: .production
        }
    }
}

extension DefaultsKey {
    /// Developer mode was switched on or off. Unset means the build's default (on in debug builds).
    static let devModeEnabled = "devModeEnabled"
}

/// Developer mode: Settings' Admin Tools section, the unlock override, and the free-tier tuning panel.
///
/// Always available in debug builds, where it starts on. In TestFlight it's off until the version row
/// in Settings is tapped `tapsToToggle` times. App Store builds never have it: the stored switch is
/// ignored and the taps do nothing. Until `AppTransaction` answers, a release build counts as production.
@Observable
@MainActor
final class DevMode {
    static let shared: DevMode = {
        let devMode = DevMode()
        devMode.resolveInBackground()
        return devMode
    }()

    static let tapsToToggle = 7
    /// Taps further apart than this start the count again.
    static let tapWindow: TimeInterval = 2

    private(set) var environment: DistributionEnvironment
    private var stored: Bool?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var taps = 0
    @ObservationIgnored private var lastTap: Date?

    init(environment: DistributionEnvironment = .assumed, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        stored = defaults.object(forKey: DefaultsKey.devModeEnabled) as? Bool
    }

    /// This build may have Developer mode.
    var isAvailable: Bool { environment.allowsDevMode }

    /// Developer mode is on. Never in production, whatever was saved.
    var isEnabled: Bool { isAvailable && (stored ?? (environment == .debug)) }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        stored = enabled
        defaults.set(enabled, forKey: DefaultsKey.devModeEnabled)
    }

    /// A tap on Settings' version row. The last of `tapsToToggle` quick taps flips Developer mode
    /// and returns what the toast says. Nil otherwise, and always in production.
    func registerVersionTap(at now: Date = .now) -> String? {
        guard isAvailable else { return nil }
        if let lastTap, now.timeIntervalSince(lastTap) > Self.tapWindow { taps = 0 }
        lastTap = now
        taps += 1
        guard taps >= Self.tapsToToggle else { return nil }
        taps = 0
        setEnabled(!isEnabled)
        return isEnabled ? "Developer mode on" : "Developer mode off"
    }

    /// For tests: what `resolve()` would have found.
    func setEnvironment(_ environment: DistributionEnvironment) {
        self.environment = environment
    }

    private func resolveInBackground() {
        Task { [weak self] in
            let environment = await DistributionEnvironment.resolve()
            self?.environment = environment
        }
    }
}
