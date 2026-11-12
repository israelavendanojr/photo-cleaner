import Foundation
import Testing
@testable import photo_swiper

/// The whole library by kind, from made-up features.
struct LibraryProfileTests {
    private let date = Date(timeIntervalSince1970: 1_762_948_800)

    private func item(bytes: Int64, video: Bool = false, screenshot: Bool = false) -> AssetFeatures {
        AssetFeatures(createdAt: date, bytes: bytes, isVideo: video, isScreenshot: screenshot)
    }

    private func make(_ features: [LibraryItem.ID: AssetFeatures], live: Set<LibraryItem.ID> = [],
                      removed: Set<LibraryItem.ID> = []) -> LibraryProfile {
        LibraryProfile.make(features: features, livePhotos: live, removed: removed)
    }

    @Test func anEmptyLibraryIsEmpty() {
        let profile = make([:])
        #expect(profile.composition.isEmpty)
        #expect(profile.totalBytes == 0)
    }

    @Test func eachItemIsOneKindInOrder() {
        let profile = make([
            "video": item(bytes: 900, video: true),
            "live": item(bytes: 300),
            "live-screenshot": item(bytes: 50, screenshot: true),
            "screenshot": item(bytes: 20, screenshot: true),
            "photo": item(bytes: 100),
        ], live: ["live", "live-screenshot", "video"])

        #expect(profile.composition[.video] == .init(count: 1, bytes: 900), "A video is a video, even if PhotoKit says live")
        #expect(profile.composition[.livePhoto] == .init(count: 2, bytes: 350))
        #expect(profile.composition[.screenshot] == .init(count: 1, bytes: 20))
        #expect(profile.composition[.photo] == .init(count: 1, bytes: 100))
        #expect(profile.totalBytes == 1_370)
    }

    @Test func deletedItemsDontCountThoughTheIndexStillHasThem() {
        let profile = make(["kept": item(bytes: 100), "deleted": item(bytes: 2_000, video: true)], removed: ["deleted"])
        #expect(profile.totalBytes == 100)
        #expect(profile.composition[.video] == nil)
    }
}
