import AVFoundation
import Foundation
import ImageIO

/// Removes the location from what's shared (JUN-8). A photo or video sent to a friend shouldn't say
/// where it was taken unless the user chose that, and the share sheet gives no way to choose, so the
/// location never leaves. Everything else stays, the capture date in particular. Pure: no PhotoKit.
enum ShareMetadata {
    /// `imageData` in the same format without its GPS metadata. Data without GPS comes back untouched.
    ///
    /// First the image is copied without decoding, with its metadata minus the GPS tags, so nothing is
    /// lost (JPEG, HEIC). ImageIO's own "exclude GPS" option isn't used: it keeps GPS in HEIC and drops
    /// all EXIF from JPEG. Formats where that copy still carries GPS (PNG keeps its EXIF chunk) are
    /// written again in their own format with the GPS removed. The result is checked either way: data
    /// that still has GPS is never returned.
    static func strippingLocation(imageData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else { throw ShareError.exportFailed }
        guard hasGPS(source) else { return imageData }

        if let copied = copyWithoutGPSTags(source), !hasGPS(copied) { return copied }
        if let written = rewriteWithoutGPS(source), !hasGPS(written) { return written }
        throw ShareError.exportFailed
    }

    private static func hasGPS(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map(hasGPS) ?? true
    }

    private static func hasGPS(_ source: CGImageSource) -> Bool {
        (0..<CGImageSourceGetCount(source)).contains { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            return properties?[kCGImagePropertyGPSDictionary] != nil
        }
    }

    /// A copy that keeps the encoded image and replaces its metadata with the same minus `exif:GPS*`.
    private static func copyWithoutGPSTags(_ source: CGImageSource) -> Data? {
        guard let type = CGImageSourceGetType(source), let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let stripped = CGImageMetadataCreateMutableCopy(metadata) else { return nil }
        var gpsPaths: [CFString] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
            let namespace = CGImageMetadataTagCopyNamespace(tag) as String?
            let name = CGImageMetadataTagCopyName(tag) as String?
            if namespace == kCGImageMetadataNamespaceExif as String, name?.hasPrefix("GPS") == true { gpsPaths.append(path) }
            return true
        }
        for path in gpsPaths { CGImageMetadataRemoveTagWithPath(stripped, nil, path) }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil) else { return nil }
        let options = [kCGImageDestinationMetadata: stripped, kCGImageDestinationMergeMetadata: false] as CFDictionary
        guard CGImageDestinationCopyImageSource(destination, source, options, nil) else { return nil }
        return output as Data
    }

    /// Every image written again in the source's format, its properties kept but the GPS dictionary
    /// (a null value over the source's own removes it).
    private static func rewriteWithoutGPS(_ source: CGImageSource) -> Data? {
        guard let type = CGImageSourceGetType(source) else { return nil }
        let count = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else { return nil }
        let properties = [kCGImagePropertyGPSDictionary: kCFNull as Any] as CFDictionary
        for index in 0..<count { CGImageDestinationAddImageFromSource(destination, source, index, properties) }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The video metadata to write: `items` without any location (ISO 6709 coordinates, place names,
    /// accuracy). Creation date, make and model stay.
    static func withoutLocation(_ items: [AVMetadataItem]) -> [AVMetadataItem] {
        items.filter { !isLocation($0) }
    }

    private static let locationIdentifiers: Set<AVMetadataIdentifier> = [
        .quickTimeMetadataLocationISO6709, .quickTimeUserDataLocationISO6709, .commonIdentifierLocation,
        .quickTimeMetadataLocationName, .quickTimeMetadataLocationBody, .quickTimeMetadataLocationNote,
        .quickTimeMetadataLocationRole, .quickTimeMetadataLocationDate,
    ]

    /// By identifier, and by name for the `com.apple.quicktime.location.*` keys without one of their own.
    private static func isLocation(_ item: AVMetadataItem) -> Bool {
        if let identifier = item.identifier, locationIdentifiers.contains(identifier) { return true }
        if item.commonKey == .commonKeyLocation { return true }
        let names = [item.identifier?.rawValue, item.key as? String]
        return names.contains { $0?.localizedCaseInsensitiveContains("location") == true }
    }
}
