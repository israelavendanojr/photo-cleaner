//
//  photo_swiperApp.swift
//  photo-swiper
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

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
    /// services, `-startAt similar|batch|video|end|celebrated|caughtUp` jumps straight to a mock state,
    /// and `-resetProgress YES` wipes saved progress first. Mocks never read or write saved progress.
    static func launch() -> FeedViewModel {
        guard LibraryServices.usesMock else {
            return FeedViewModel(library: PhotoKitLibrary(), builder: PhotoKitFeedBuilder(), store: savedProgress())
        }
        if let raw = UserDefaults.standard.string(forKey: "startAt"), let start = MockStart(rawValue: raw) {
            return .mock(startingAt: start)
        }
        return FeedViewModel(library: MockPhotoLibrary(), builder: MockFeedBuilder())
    }

    static func savedProgress() -> any ProgressStoring {
        do {
            let store = try SwiftDataProgressStore.onDisk()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "resetProgress") { store.reset() }
            #endif
            return store
        } catch {
            // Keep the app usable; progress just won't outlive this launch.
            assertionFailure("Couldn't open saved progress: \(error)")
            return InMemoryProgressStore()
        }
    }
}
