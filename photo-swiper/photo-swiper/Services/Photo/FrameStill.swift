import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// The still a frame chosen from a Live Photo's motion becomes (JUN-106). Files in, files out, with no
/// PhotoKit, so it's tested on the mock motion.
///
/// The frame is drawn upright (the video's preferred transform) and encoded as HEIC. It carries the
/// original still's metadata (date, camera, location), marked upright. The maker note is dropped, because
/// it holds the Live Photo's content identifier, and the still must never pair with the motion again.
enum FrameStill {
    /// The original still's properties, ready for a frame: orientation 1, since the frame's pixels are already
    /// upright; no pixel sizes, which the encoder writes; and no Apple maker note.
    static func properties(from original: [CFString: Any]) -> [CFString: Any] {
        var properties = original
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = nil
        properties[kCGImagePropertyPixelHeight] = nil
        properties[kCGImagePropertyMakerAppleDictionary] = nil
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            properties[kCGImagePropertyExifDictionary] = exif
        }
        return properties
    }

    /// The still at `url`'s properties, ready for a frame. Empty if they can't be read; the copy still gets
    /// its date and location from the library (`LibraryCopy`).
    static func metadata(ofStillAt url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }
        return properties(from: original)
    }

    /// Writes the exact frame of `video` at `time`, upright, as HEIC with `metadata`, to `url`. Returns the
    /// frame's size in pixels.
    static func write(frameOf video: URL, at time: TimeInterval, metadata: [CFString: Any], to url: URL) async throws -> CGSize {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        // The frame the user picked, not a nearby one.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image: CGImage
        do {
            image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        } catch {
            throw EditError.exportFailed
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw EditError.exportFailed
        }
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EditError.exportFailed }
        return CGSize(width: image.width, height: image.height)
    }

    /// A small, upright frame of `video` near `time`, for the bin's row.
    static func thumbnail(of video: URL, at time: TimeInterval, maxSide: CGFloat) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }
}
