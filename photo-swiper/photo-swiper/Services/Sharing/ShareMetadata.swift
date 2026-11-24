import AVFoundation
import Foundation
import ImageIO

/// Removes the location from what's shared (JUN-8). A photo or video sent to a friend shouldn't say
/// where it was taken unless the user chose that, and the share sheet gives no way to choose, so the
/// location never leaves. Everything else stays, the capture date in particular. Pure: no PhotoKit.
enum ShareMetadata {
    /// `imageData` in the same format without its location: GPS coordinates, and the place names IPTC and
    /// XMP can carry (city, state, country, sub-location). Data without any comes back untouched.
    ///
    /// First the image is copied without decoding, with its metadata minus the location tags, so nothing
    /// is lost (JPEG, HEIC). ImageIO's own "exclude GPS" option isn't used: it keeps GPS in HEIC and drops
    /// all EXIF from JPEG. Formats where that copy still carries a location (PNG keeps its EXIF chunk) are
    /// written again in their own format without it. The result is checked either way: data that still
    /// has a location is never returned.
    static func strippingLocation(imageData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else { throw ShareError.exportFailed }
        guard hasLocation(source) else { return imageData }

        if let copied = copyWithoutLocationTags(source), !hasLocation(copied) { return copied }
        if let written = rewriteWithoutLocation(source), !hasLocation(written) { return written }
        throw ShareError.exportFailed
    }

    /// IPTC's place names, as ImageIO reads them into `kCGImagePropertyIPTCDictionary`.
    private static let iptcLocationKeys: [CFString] = [
        kCGImagePropertyIPTCCity, kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCProvinceState,
        kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
    ]

    /// XMP tags that hold a location, by namespace: GPS in EXIF's, and place names in Photoshop's and IPTC's.
    private static let xmpLocationTags: [String: (String) -> Bool] = [
        kCGImageMetadataNamespaceExif as String: { $0.hasPrefix("GPS") },
        kCGImageMetadataNamespaceExifAux as String: { $0.hasPrefix("GPS") },
        kCGImageMetadataNamespacePhotoshop as String: { ["City", "State", "Country"].contains($0) },
        kCGImageMetadataNamespaceIPTCCore as String: { ["Location", "CountryCode"].contains($0) },
        kCGImageMetadataNamespaceIPTCExtension as String: { ["LocationShown", "LocationCreated"].contains($0) },
    ]

    private static func isLocationTag(_ tag: CGImageMetadataTag) -> Bool {
        guard let namespace = CGImageMetadataTagCopyNamespace(tag) as String?, let name = CGImageMetadataTagCopyName(tag) as String?
        else { return false }
        return xmpLocationTags[namespace]?(name) == true
    }

    /// The paths of `metadata`'s top-level tags that hold a location.
    private static func locationPaths(in metadata: CGImageMetadata) -> [CFString] {
        var paths: [CFString] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
            if isLocationTag(tag) { paths.append(path) }
            return true
        }
        return paths
    }

    private static func hasLocation(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map(hasLocation) ?? true
    }

    private static func hasLocation(_ source: CGImageSource) -> Bool {
        (0..<CGImageSourceGetCount(source)).contains { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            if properties?[kCGImagePropertyGPSDictionary] != nil { return true }
            let iptc = properties?[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            if iptcLocationKeys.contains(where: { iptc[$0] != nil }) { return true }
            guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { return false }
            return !locationPaths(in: metadata).isEmpty
        }
    }

    /// A copy that keeps the encoded image and replaces its metadata with the same minus its location tags.
    private static func copyWithoutLocationTags(_ source: CGImageSource) -> Data? {
        guard let type = CGImageSourceGetType(source), let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let stripped = CGImageMetadataCreateMutableCopy(metadata) else { return nil }
        for path in locationPaths(in: metadata) { CGImageMetadataRemoveTagWithPath(stripped, nil, path) }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil) else { return nil }
        let options = [kCGImageDestinationMetadata: stripped, kCGImageDestinationMergeMetadata: false] as CFDictionary
        guard CGImageDestinationCopyImageSource(destination, source, options, nil) else { return nil }
        return output as Data
    }

    /// Every image written again in the source's format, its properties kept but GPS and IPTC's place
    /// names (a null value over the source's own removes it).
    private static func rewriteWithoutLocation(_ source: CGImageSource) -> Data? {
        guard let type = CGImageSourceGetType(source) else { return nil }
        let count = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else { return nil }
        for index in 0..<count {
            var properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: kCFNull as Any]
            let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            if var iptc = original?[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                for key in iptcLocationKeys { iptc[key] = nil }
                properties[kCGImagePropertyIPTCDictionary] = iptc.isEmpty ? kCFNull as Any : iptc
            }
            CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Exports `session` to `url` as a QuickTime movie without location, then opens the file and checks it,
    /// throwing `ShareError.exportFailed` (and removing it) if any location is left. The asset's metadata
    /// is written without location items, AVFoundation's sharing filter takes location from the tracks
    /// too, and `creationDate` is added when the asset carries none (a slow-motion composition has none).
    static func exportWithoutLocation(_ session: AVAssetExportSession, to url: URL, creationDate: Date?) async throws {
        var metadata = withoutLocation(try await session.asset.load(.metadata))
        if let creationDate, !metadata.contains(where: { $0.identifier == .quickTimeMetadataCreationDate || $0.commonKey == .commonKeyCreationDate }) {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataCreationDate
            item.value = ISO8601DateFormatter().string(from: creationDate) as NSString
            metadata.append(item)
        }
        session.metadata = metadata
        session.metadataItemFilter = .forSharing()
        try await session.export(to: url, as: .mov)
        guard try await !containsLocation(AVURLAsset(url: url)) else {
            try? FileManager.default.removeItem(at: url)
            throw ShareError.exportFailed
        }
    }

    /// Whether `asset` carries a location anywhere: in its own metadata, a track's, or a timed metadata
    /// track. Timed tracks other than QuickTime's own (a GoPro's or a drone's GPS stream) can't be read
    /// here, so they count as a location: failing to share beats leaking where someone was.
    static func containsLocation(_ asset: AVAsset) async throws -> Bool {
        if try await asset.load(.metadata).contains(where: isLocation) { return true }
        for track in try await asset.load(.tracks) {
            if try await track.load(.metadata).contains(where: isLocation) { return true }
            guard track.mediaType == .metadata else { continue }
            for description in try await track.load(.formatDescriptions) {
                guard description.mediaSubType.rawValue == kCMMetadataFormatType_Boxed else { return true }
                let identifiers = CMMetadataFormatDescriptionGetIdentifiers(description) as? [String] ?? []
                if identifiers.contains(where: isLocationName) { return true }
            }
        }
        return false
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
        return [item.identifier?.rawValue, item.key as? String].contains { $0.map(isLocationName) == true }
    }

    private static func isLocationName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("location") || name.localizedCaseInsensitiveContains("ISO6709")
            || name.localizedCaseInsensitiveContains("gps")
    }
}
