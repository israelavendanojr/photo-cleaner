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
    /// Mock services by default. Pass `-startAt similar|batch|video|end|celebrated|caughtUp`
    /// as a launch argument to jump straight to a state.
    static func launch() -> FeedViewModel {
        if let raw = UserDefaults.standard.string(forKey: "startAt"), let start = MockStart(rawValue: raw) {
            return .mock(startingAt: start)
        }
        return FeedViewModel(library: MockPhotoLibrary(), builder: MockFeedBuilder())
    }
}
