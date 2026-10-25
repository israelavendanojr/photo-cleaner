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
    /// services, `-startAt similar|batch|video|end|celebrated|resting|welcomeBack|paywall|caughtUp|onboarding`
    /// jumps straight to a mock state, `-resetProgress YES` wipes saved progress first, and
    /// `-resetOnboarding YES` shows onboarding and the swipe hint again. `-unlocked YES|NO` sets the
    /// stand-in purchase (mocks start locked). Mocks never read or write saved progress and never
    /// start the feature index. Release builds always run on the real library.
    static func launch() -> FeedViewModel {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasOnboarded)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.hasSeenSwipeHint)
        }
        if LibraryServices.usesMock {
            let entitlements = EntitlementServices.make(mock: true)
            if let raw = UserDefaults.standard.string(forKey: "startAt"), let start = MockStart(rawValue: raw) {
                return .mock(startingAt: start, entitlements: entitlements)
            }
            return FeedViewModel(library: MockPhotoLibrary(), builder: MockFeedBuilder(), entitlements: entitlements)
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
                library: library, builder: PhotoKitFeedBuilder(), store: InMemoryProgressStore(), entitlements: entitlements
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
            firstSessionMinimum: FeedViewModel.onboardingPreparingMinimum
        )
    }
}
