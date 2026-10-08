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
    /// The real library by default. In debug builds, `-mockLibrary YES` uses mock services, and
    /// `-startAt similar|batch|video|end|celebrated|caughtUp` jumps straight to a mock state.
    static func launch() -> FeedViewModel {
        guard LibraryServices.usesMock else {
            return FeedViewModel(library: PhotoKitLibrary(), builder: PhotoKitFeedBuilder())
        }
        if let raw = UserDefaults.standard.string(forKey: "startAt"), let start = MockStart(rawValue: raw) {
            return .mock(startingAt: start)
        }
        return FeedViewModel(library: MockPhotoLibrary(), builder: MockFeedBuilder())
    }
}
