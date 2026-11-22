import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import photo_swiper

/// Choosing a Live Photo's key photo from its motion (JUN-106): which frame counts as the original, what a
/// chosen frame's flatten holds, and the still a chosen frame becomes.
@MainActor
struct KeyFrameTests {
    private let frame = 1.0 / 30

    @Test func theKeyPhotosOwnFrameAndItsNeighbourCountAsTheOriginal() {
        #expect(KeyFrame.isOriginal(time: 1.25, photoTime: 1.25, frameDuration: frame))
        #expect(KeyFrame.isOriginal(time: 1.25 + frame * 0.9, photoTime: 1.25, frameDuration: frame))
        #expect(!KeyFrame.isOriginal(time: 1.25 + frame * 2, photoTime: 1.25, frameDuration: frame))
        #expect(!KeyFrame.isOriginal(time: 0, photoTime: 1.25, frameDuration: frame))
    }

    @Test func withNoKnownKeyPhotoEveryFrameIsTheOriginal() {
        #expect(KeyFrame.isOriginal(time: 0.2, photoTime: nil, frameDuration: frame))
    }

    @Test func theOriginalFrameFlattensLosslessly() {
        let edit = KeyFrame.flatten(at: 1.26, photoTime: 1.25, frameDuration: frame,
                                    frameSize: CGSize(width: 1440, height: 1080), stillBytes: 1_800_000)
        #expect(edit.live == LiveEdit(keyFrameTime: nil, stillBytes: 1_800_000), "Choosing it again goes back to the lossless path")
    }

    @Test func anotherFrameKeepsItsTimeAndEstimatesItsSizeFromItsPixels() throws {
        let edit = KeyFrame.flatten(at: 0.5, photoTime: 1.25, frameDuration: frame,
                                    frameSize: CGSize(width: 1440, height: 1080), stillBytes: 1_800_000)
        let live = try #require(edit.live)
        #expect(live.keyFrameTime == 0.5)
        #expect(live.stillBytes == Int64(1440.0 * 1080 * KeyFrame.bytesPerPixel))
        #expect(edit.isFlatten && !edit.isTrimmed && !edit.isCompressed)
    }

    @Test func aFrameOfUnknownSizeClaimsNoSavings() {
        let edit = KeyFrame.flatten(at: 0.5, photoTime: 1.25, frameDuration: frame, frameSize: .zero, stillBytes: 1_800_000)
        #expect(edit.live == LiveEdit(keyFrameTime: 0.5, stillBytes: nil))
    }

    // MARK: The still

    @Test func theFramesMetadataIsUprightAndNoLongerPairsWithTheMotion() throws {
        let original: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyPixelWidth: 4032,
            kCGImagePropertyPixelHeight: 3024,
            kCGImagePropertyMakerAppleDictionary: ["17": "content-identifier"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6, kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:22 10:00:00", kCGImagePropertyExifPixelXDimension: 4032],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.3],
        ]

        let still = FrameStill.properties(from: original)

        #expect(still[kCGImagePropertyOrientation] as? Int == 1, "The frame is drawn upright, so it says so")
        #expect(still[kCGImagePropertyPixelWidth] == nil)
        #expect(still[kCGImagePropertyMakerAppleDictionary] == nil, "Without the content identifier, it can't re-pair")
        let tiff = try #require(still[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFOrientation] as? Int == 1)
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "iPhone")
        let exif = try #require(still[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:22 10:00:00", "The date stays")
        #expect(exif[kCGImagePropertyExifPixelXDimension] == nil)
        #expect(still[kCGImagePropertyGPSDictionary] != nil, "The location stays")
    }

    @Test func theMockMotionsFrameIsWrittenUprightWithTheStillsDate() async throws {
        let video = try #require(Bundle.main.url(forResource: "mock-live", withExtension: "mov"))
        let url = FileManager.default.temporaryDirectory.appending(path: "frame-test-\(UUID().uuidString).heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:22 10:00:00"]]

        let size = try await FrameStill.write(frameOf: video, at: 0.5, metadata: metadata, to: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == Int(size.width))
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == Int(size.height))
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:22 10:00:00")
    }
}
