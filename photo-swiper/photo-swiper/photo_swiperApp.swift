//
//  photo_swiperApp.swift
//  photo-swiper
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

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
    /// services, `-startAt similar|batch|video|pending|outOfSwipes|caughtUp|onboarding`
    /// jumps straight to a mock state, `-resetProgress YES` wipes saved progress first, and
    /// `-resetOnboarding YES` shows onboarding and the swipe hint again. `-unlocked YES|NO` sets the
    /// stand-in purchase (mocks start locked). Mocks never read or write the real saved progress and
    /// never start the feature index; `-mockProgress YES` gives them their own on-disk store, so a
    /// relaunch resumes the mock deck. `-logSimilarity YES` logs each session's similar groups and near misses
    /// (category "similar"). `-swipesLeft N` sets the free swipes left, and `-refillSoon YES` refills
    /// every minute instead of every six hours. Release builds always run on the real library.
    static func launch() -> FeedViewModel {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasOnboarded)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasSeenSwipeHint)
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
                             allowanceTunables: allowanceTunables, notifier: notifier)
            }
            return FeedViewModel(
                library: MockPhotoLibrary(), builder: MockFeedBuilder(), store: mockProgressStore(), entitlements: entitlements,
                allowanceStore: SwipeAllowanceStore(initial: allowance), allowanceTunables: allowanceTunables, notifier: notifier
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
            assertionFailure("Couldn't open saved progress: \(error)")
            return FeedViewModel(
                library: library, builder: PhotoKitFeedBuilder(), store: InMemoryProgressStore(), entitlements: entitlements,
                allowanceStore: SwipeAllowanceStore(defaults: .standard), allowanceTunables: allowanceTunables
            )
        }
        let store = SwiftDataProgressStore(container: container)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetProgress") { store.reset() }
        #endif
        let index = FeatureIndex(container: container)
        let indexer = LibraryIndexer(source: PhotoKitIndexSource(), analyzer: VisionImageAnalyzer(), index: index)
        return FeedViewModel(
            library: library,
            builder: PhotoKitFeedBuilder(index: index),
            store: store,
            entitlements: entitlements,
            indexScheduler: IndexScheduler(indexer: indexer, library: library),
            firstSessionMinimum: FeedViewModel.onboardingPreparingMinimum,
            allowanceStore: SwipeAllowanceStore(defaults: .standard),
            allowanceTunables: allowanceTunables,
            notifier: RefillNotifier(center: SystemNotificationCenter(), defaults: .standard)
        )
    }

    static var allowanceTunables: SwipeAllowance.Tunables {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "refillSoon") { return .refillSoon }
        #endif
        return .standard
    }

    #if DEBUG
    /// `-mockProgress YES`: saved mock progress in its own file, apart from the real one. Otherwise in memory.
    static func mockProgressStore() -> any ProgressStoring {
        guard UserDefaults.standard.bool(forKey: "mockProgress") else { return InMemoryProgressStore() }
        let url = URL.applicationSupportDirectory.appending(path: "mock-progress.store")
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        guard let container = try? SwiftDataProgressStore.makeContainer(url: url) else { return InMemoryProgressStore() }
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
