//
//  photo_swiperApp.swift
//  photo-swiper
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

import OSLog
import SwiftData
import SwiftUI

@main
struct photo_swiperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var feed = FeedViewModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(feed)
                .tint(DS.Palette.ink)
                // The palette is light-only for now.
                .preferredColorScheme(.light)
        }
    }
}

private extension FeedViewModel {
    /// The real library and saved progress by default. In debug builds, `-mockLibrary YES` uses mock
    /// services, `-startAt similar|batch|duplicates|video|pending|outOfSwipes|caughtUp|onboarding`
    /// jumps straight to a mock state, `-resetProgress YES` wipes saved progress first, and
    /// `-resetOnboarding YES` shows onboarding and the swipe hint again. `-unlocked YES|NO` forces the
    /// unlock on or off (saved for the real store; mocks start locked). Mocks never read or write the real saved progress and
    /// never start the feature index; `-mockProgress YES` gives them their own on-disk store, so a
    /// relaunch resumes the mock deck. `-logSimilarity YES` logs each session's similar groups and near misses
    /// (category "similar"). `-swipesLeft N` sets the free swipes left, and `-refillSoon YES` refills
    /// every minute instead of every six hours. `-simulateComplete YES` shows the library as 100% reviewed
    /// (display only, nothing saved) and forgets that the confetti played, so it plays on the Library tab.
    /// `-resetDevMode YES` turns Developer mode back on, its debug default, whatever an earlier run saved,
    /// so UI tests always find the Admin tab. `-mockHistory YES` fills the mock cleanup history with about ten
    /// weeks of made-up deletes, for the Library dashboard's chart; `-showLibrary YES` opens on that tab.
    /// Release builds always run on the real library.
    static func launch() -> FeedViewModel {
        let vm = launchServices()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "simulateComplete") {
            vm.admin.debugResetCelebration()
            vm.admin.debugSetSimulatesComplete(true)
        }
        #endif
        return vm
    }

    /// The view model for `launch()`, before display-only debug overrides.
    private static func launchServices() -> FeedViewModel {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasOnboarded)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasSeenSwipeHint)
            UserDefaults.standard.set(true, forKey: DefaultsKey.debugShowOnboarding)
        }
        // `-resetUpsell YES` forgets when the delete offer last showed, so it's due again.
        if UserDefaults.standard.bool(forKey: "resetUpsell") {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.deleteUpsellShownAt)
        }
        // `-resetDevMode YES`: Developer mode is saved, so a test that turned it off would hide the Admin tab
        // from every later run. Uses the normal switch, which debug builds always allow.
        if UserDefaults.standard.bool(forKey: "resetDevMode") {
            DevMode.shared.setEnabled(true)
        }
        // `-resetTunables YES` drops Developer mode's saved free-limit and feature overrides, so UI tests run on the defaults.
        if UserDefaults.standard.bool(forKey: "resetTunables") {
            FreeTierTunables.shared.resetToDefaults()
            FeatureAvailabilityTunables.shared.resetToDefaults()
        }
        if LibraryServices.usesMock {
            let entitlements = EntitlementServices.make(mock: true)
            let suite = "mock.reminders"
            let reminderDefaults = UserDefaults(suiteName: suite) ?? .standard
            reminderDefaults.removePersistentDomain(forName: suite)
            let notifier = RefillNotifier(center: SystemNotificationCenter(), defaults: reminderDefaults)
            let allowance = debugSwipesLeft.map { SwipeAllowance(balance: $0, tunables: allowanceTunables, now: .now) }
            if let raw = UserDefaults.standard.string(forKey: "startAt"), let start = MockStart(rawValue: raw) {
                return .mock(startingAt: start, entitlements: entitlements, allowance: allowance,
                             freeTier: .shared, features: .shared, notifier: notifier)
            }
            return FeedViewModel(
                library: MockPhotoLibrary(), builder: MockFeedBuilder(), store: mockProgressStore(), entitlements: entitlements,
                allowanceStore: SwipeAllowanceStore(initial: allowance), freeTier: .shared, features: .shared, notifier: notifier,
                deviceStorage: MockDeviceStorage()
            )
        }
        if let left = debugSwipesLeft {
            SwipeAllowanceStore(defaults: .standard).save(SwipeAllowance(balance: left, tunables: allowanceTunables, now: .now))
        }
        #endif
        return real(entitlements: EntitlementServices.make(mock: false))
    }

    /// Saved progress and the feature index share one on-disk container.
    static func real(entitlements: any EntitlementStore) -> FeedViewModel {
        let library = PhotoKitLibrary()
        let container: ModelContainer
        do {
            container = try SwiftDataProgressStore.makeContainer()
        } catch {
            // Keep the app usable; progress just won't outlive this launch, and nothing is indexed.
            // The saved file is left alone, and the user is told rather than seeing their pile vanish.
            Logger.app(category: "progress").error("Couldn't open saved progress: \(error)")
            assertionFailure("Couldn't open saved progress: \(error)")
            return FeedViewModel(
                library: library, builder: PhotoKitFeedBuilder(), store: InMemoryProgressStore(), entitlements: entitlements,
                allowanceStore: SwipeAllowanceStore(defaults: .standard), freeTier: .shared, features: .shared,
                progressLoadFailed: true
            )
        }
        let store = SwiftDataProgressStore(container: container)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetProgress") {
            store.reset()
            try? FileManager.default.removeItem(at: DashboardController.defaultCacheURL)
        }
        #endif
        let index = FeatureIndex(container: container)
        let indexer = LibraryIndexer(source: PhotoKitIndexSource(), analyzer: VisionImageAnalyzer(), index: index,
                                     canPrune: { library.currentAccess() == .full })
        return FeedViewModel(
            library: library,
            builder: PhotoKitFeedBuilder(index: index),
            store: store,
            entitlements: entitlements,
            indexScheduler: IndexScheduler(indexer: indexer, library: library),
            firstSessionMinimum: FeedViewModel.onboardingPreparingMinimum,
            allowanceStore: SwipeAllowanceStore(defaults: .standard),
            freeTier: .shared,
            features: .shared,
            notifier: RefillNotifier(center: SystemNotificationCenter(), defaults: .standard),
            dashboardCache: DashboardController.defaultCacheURL,
            deviceStorage: VolumeStorageReader()
        )
    }

    /// The live free-tier tunables (`-refillSoon YES` is applied in `FreeTierLimits.launch`).
    static var allowanceTunables: SwipeAllowance.Tunables { FreeTierTunables.shared.limits.allowance }

    #if DEBUG
    /// `-mockProgress YES`: saved mock progress in its own file, apart from the real one. Otherwise in memory.
    /// `-mockHistory YES` gives an empty history about ten weeks of made-up cleanups.
    static func mockProgressStore() -> any ProgressStoring {
        let store = savedMockProgressStore() ?? InMemoryProgressStore()
        if UserDefaults.standard.bool(forKey: "mockHistory"), store.cleanupHistory().isEmpty {
            store.recordCleanup(MockHistory.entries(now: .now))
        }
        return store
    }

    private static func savedMockProgressStore() -> (any ProgressStoring)? {
        guard UserDefaults.standard.bool(forKey: "mockProgress") else { return nil }
        let url = URL.applicationSupportDirectory.appending(path: "mock-progress.store")
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        guard let container = try? SwiftDataProgressStore.makeContainer(url: url) else { return nil }
        let store = SwiftDataProgressStore(container: container, defaults: nil)
        if UserDefaults.standard.bool(forKey: "resetProgress") { store.reset() }
        return store
    }

    /// `-swipesLeft N`.
    static var debugSwipesLeft: Int? {
        UserDefaults.standard.object(forKey: "swipesLeft") == nil ? nil : UserDefaults.standard.integer(forKey: "swipesLeft")
    }
    #endif
}
