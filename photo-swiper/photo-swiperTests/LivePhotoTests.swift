import Foundation
import Testing
@testable import photo_swiper

/// Knowing an item is a Live Photo (JUN-105): the saved flag, how it's set, and the fallback for
/// items saved before it existed.
@MainActor
struct LivePhotoTests {
    /// A builder that only answers which items are Live Photos.
    private struct LiveBuilder: FeedBuilding {
        let live: Set<LibraryItem.ID>

        func makeSession(number: Int, options: FeedOptions) async -> Session { Session(number: number, cards: []) }
        func livePhotoIDs() async -> Set<LibraryItem.ID> { live }
    }

    @Test func itemsSavedBeforeTheFlagStillDecode() throws {
        let item = LibraryItem(id: "old", kind: .photo, date: .now, location: nil, bytes: 1, image: .bundled("photo-cafe"))
        let json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        #expect(!json.contains("isLivePhoto"), "A nil flag isn't written")
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        #expect(decoded.isLivePhoto == nil)
    }

    @Test func theFlagRoundTrips() throws {
        var item = PreviewSamples.plainPhoto
        item.isLivePhoto = true
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.isLivePhoto == true)
        #expect(decoded == item)
    }

    @Test func theMapperMarksLivePhotosButNeverVideos() {
        let photo = AssetFeatures(createdAt: .now, bytes: 1)
        var video = photo
        video.isVideo = true
        video.duration = 3

        #expect(AssetMapper.item(id: "a", features: photo, location: nil, isLivePhoto: true).isLivePhoto == true)
        #expect(AssetMapper.item(id: "b", features: photo, location: nil, isLivePhoto: false).isLivePhoto == false)
        #expect(AssetMapper.item(id: "c", features: video, location: nil, isLivePhoto: true).isLivePhoto == false)
    }

    @Test func theViewModelTrustsTheFlagAndFallsBackToTheBuilder() async {
        let vm = FeedViewModel(library: FakeLibrary(), builder: LiveBuilder(live: ["old-live"]), entitlements: TestEntitlements(),
                               defaults: freshDefaults())
        func item(_ id: String, live: Bool?) -> LibraryItem {
            var item = LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: 1, image: .bundled("photo-cafe"))
            item.isLivePhoto = live
            return item
        }

        #expect(await vm.isLivePhoto(item("new-live", live: true)))
        #expect(await !vm.isLivePhoto(item("old-live", live: false)), "A saved flag wins over the builder")
        #expect(await vm.isLivePhoto(item("old-live", live: nil)), "Saved before the flag: the builder knows")
        #expect(await !vm.isLivePhoto(item("old-still", live: nil)))
    }

    @Test func theMockDeckOpensOnALivePhoto() throws {
        let session = MockFeedBuilder().makeSessionNow(number: 1)
        let first = try #require(session.cards.first?.items.first)
        #expect(first.isLivePhoto == true)
        let others = session.cards.dropFirst().flatMap(\.items)
        #expect(others.allSatisfy { $0.isLivePhoto != true }, "Only the first card is Live")
    }
}
