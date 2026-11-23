import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import photo_swiper

/// Everything shared leaves without its location (JUN-8): GPS from photos, location items from videos.
/// The capture date and the rest of the metadata stay.
struct ShareMetadataTests {
    /// A small image of `type` carrying GPS, a capture date and a camera make, as a camera would write it.
    private func image(_ type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let cgImage = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.33,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.03,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2019:07:04 18:30:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple"],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func type(_ data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType) as String?
    }

    @Test(arguments: [UTType.jpeg, .heic, .png])
    func gpsIsRemovedAndTheRestIsKept(_ format: UTType) throws {
        let original = try image(format)
        #expect(try properties(original)[kCGImagePropertyGPSDictionary] != nil, "The fixture has GPS to remove")

        let stripped = try ShareMetadata.strippingLocation(imageData: original)
        let props = try properties(stripped)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect(type(stripped) == format.identifier, "Same format")
        if format != .png {
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2019:07:04 18:30:00", "Capture date kept")
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "Apple")
        }
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 8)
    }

    @Test func dataThatIsntAnImageThrows() {
        #expect(throws: ShareError.exportFailed) {
            try ShareMetadata.strippingLocation(imageData: Data("not an image".utf8))
        }
    }

    private func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private func metadataItem(key: String, keySpace: AVMetadataKeySpace, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSString
        item.keySpace = keySpace
        item.value = value as NSString
        return item
    }

    @Test func videoLocationItemsAreDroppedAndTheRestKept() {
        let items = [
            metadataItem(.quickTimeMetadataLocationISO6709, "+37.3300-122.0300/"),
            metadataItem(.quickTimeUserDataLocationISO6709, "+37.3300-122.0300/"),
            metadataItem(.commonIdentifierLocation, "+37.3300-122.0300/"),
            metadataItem(key: "com.apple.quicktime.location.name", keySpace: .quickTimeMetadata, "Cupertino"),
            metadataItem(key: "com.apple.quicktime.location.accuracy.horizontal", keySpace: .quickTimeMetadata, "5"),
            metadataItem(.quickTimeMetadataCreationDate, "2019-07-04T18:30:00-0700"),
            metadataItem(.quickTimeMetadataMake, "Apple"),
            metadataItem(.quickTimeMetadataModel, "iPhone"),
        ]

        let kept = ShareMetadata.withoutLocation(items).compactMap(\.identifier)
        #expect(kept == [.quickTimeMetadataCreationDate, .quickTimeMetadataMake, .quickTimeMetadataModel])
    }
}
