import Foundation
import Testing
@testable import photo_swiper

/// The whole library by kind and month, from made-up features. Fixed time and calendar.
struct LibraryProfileTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 12 Nov 2025, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_762_948_800)
    private let day: TimeInterval = 86_400

    private func item(_ daysAgo: Double, bytes: Int64, video: Bool = false, screenshot: Bool = false) -> AssetFeatures {
        AssetFeatures(createdAt: now.addingTimeInterval(-daysAgo * day), bytes: bytes, isVideo: video, isScreenshot: screenshot)
    }

    private func make(_ features: [LibraryItem.ID: AssetFeatures], live: Set<LibraryItem.ID> = [], decided: Set<LibraryItem.ID> = []) -> LibraryProfile {
        LibraryProfile.make(features: features, livePhotos: live, decided: decided, now: now, calendar: Self.calendar)
    }

    @Test func anEmptyLibraryIsEmpty() {
        let profile = make([:])
        #expect(profile.composition.isEmpty)
        #expect(profile.monthly.isEmpty)
        #expect(profile.totalBytes == 0)
        #expect(profile.oldestUnreviewed == nil)
    }

    @Test func eachItemIsOneKindInOrder() {
        let profile = make([
            "video": item(1, bytes: 900, video: true),
            "live": item(1, bytes: 300),
            "live-screenshot": item(1, bytes: 50, screenshot: true),
            "screenshot": item(1, bytes: 20, screenshot: true),
            "photo": item(1, bytes: 100),
        ], live: ["live", "live-screenshot", "video"])

        #expect(profile.composition[.video] == .init(count: 1, bytes: 900), "A video is a video, even if PhotoKit says live")
        #expect(profile.composition[.livePhoto] == .init(count: 2, bytes: 350))
        #expect(profile.composition[.screenshot] == .init(count: 1, bytes: 20))
        #expect(profile.composition[.photo] == .init(count: 1, bytes: 100))
        #expect(profile.totalBytes == 1_370)
    }

    @Test func monthsStartOnTheFirstAtMidnight() throws {
        // 31 Oct 2025 23:00 and 1 Nov 2025 01:00 UTC fall in different months.
        let october = Date(timeIntervalSince1970: 1_761_951_600)
        let november = Date(timeIntervalSince1970: 1_761_958_800)
        let profile = make([
            "a": AssetFeatures(createdAt: october, bytes: 1),
            "b": AssetFeatures(createdAt: november, bytes: 2),
            "c": AssetFeatures(createdAt: now, bytes: 4),
        ])
        let months = profile.monthly.keys.sorted()
        #expect(months.count == 2)
        #expect(months.allSatisfy { Self.calendar.component(.day, from: $0) == 1 && Self.calendar.component(.hour, from: $0) == 0 })
        #expect(profile.monthly[months[1]] == .init(count: 2, bytes: 6))
    }

    @Test func recentlyIsTheLastNinetyDaysAndNothingFromTheFuture() {
        let profile = make([
            "in": item(89, bytes: 10),
            "out": item(91, bytes: 1_000),
            "future": item(-2, bytes: 5_000),
        ])
        #expect(profile.addedRecently == 10)
    }

    @Test func theOldestUnreviewedSkipsDecidedItems() {
        let profile = make([
            "decided-oldest": item(4_000, bytes: 1),
            "unreviewed": item(2_000, bytes: 1),
            "newer": item(10, bytes: 1),
        ], decided: ["decided-oldest"])
        #expect(profile.oldestUnreviewed == now.addingTimeInterval(-2_000 * day))
    }
}
