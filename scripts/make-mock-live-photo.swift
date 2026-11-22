#!/usr/bin/env swift
// Makes the mock library's Live Photo: a HEIC still and a short QuickTime clip paired the way the camera
// pairs them, so `PHLivePhoto.request(withResourceFileURLs:)` accepts them (JUN-105).
//
// The two files share a content identifier: the still's Apple maker note key 17 and the clip's
// `com.apple.quicktime.content.identifier`. The clip marks where the still sits in it with a
// `com.apple.quicktime.still-image-time` timed-metadata sample. The motion is a slow zoom on the still
// itself, so playing and scrubbing look like the same photo.
//
// Usage: swift scripts/make-mock-live-photo.swift <still.png> <output-directory>
// Writes mock-live.heic and mock-live.mov. The app's copies are in photo-swiper/photo-swiper/Resources.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift scripts/make-mock-live-photo.swift <still.png> <output-directory>")
    exit(1)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let identifier = UUID().uuidString
/// Where the still sits in the clip, as `MockLivePhoto.keyFrameTime` expects.
let stillTime = 1.25
let duration = 2.5
let fps: Int32 = 30
let width = 720, height = 1080

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("can't read \(input.path)") }

// MARK: Still

let stillURL = output.appendingPathComponent("mock-live.heic")
try? FileManager.default.removeItem(at: stillURL)
guard let destination = CGImageDestinationCreateWithURL(stillURL as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
    fail("no HEIC encoder")
}
let stillProperties: [CFString: Any] = [
    kCGImagePropertyMakerAppleDictionary: ["17": identifier],
    kCGImageDestinationLossyCompressionQuality: 0.6,
]
CGImageDestinationAddImage(destination, image, stillProperties as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("couldn't write the still") }

// MARK: Clip

let clipURL = output.appendingPathComponent("mock-live.mov")
try? FileManager.default.removeItem(at: clipURL)
let writer: AVAssetWriter
do { writer = try AVAssetWriter(outputURL: clipURL, fileType: .mov) } catch { fail("\(error)") }

let contentID = AVMutableMetadataItem()
contentID.keySpace = .quickTimeMetadata
contentID.key = "com.apple.quicktime.content.identifier" as NSString
contentID.value = identifier as NSString
contentID.dataType = "com.apple.metadata.datatype.UTF-8"
writer.metadata = [contentID]

let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000],
])
video.expectsMediaDataInRealTime = false
let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])

let specification: NSDictionary = [
    kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "mdta/com.apple.quicktime.still-image-time",
    kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: "com.apple.metadata.datatype.int8",
]
var format: CMFormatDescription?
CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
    allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
    metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &format
)
let metadata = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
let timedMetadata = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)

writer.add(video)
writer.add(metadata)
guard writer.startWriting() else { fail("\(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)

let stillMark = AVMutableMetadataItem()
stillMark.keySpace = AVMetadataKeySpace(rawValue: "mdta")
stillMark.key = "com.apple.quicktime.still-image-time" as NSString
stillMark.value = NSNumber(value: Int8(-1))
stillMark.dataType = "com.apple.metadata.datatype.int8"
let markRange = CMTimeRange(start: CMTime(seconds: stillTime, preferredTimescale: 600), duration: CMTime(value: 1, timescale: 600))
while !metadata.isReadyForMoreMediaData { usleep(1_000) }
timedMetadata.append(AVTimedMetadataGroup(items: [stillMark], timeRange: markRange))
metadata.markAsFinished()

let frameCount = Int(duration * Double(fps))
for frame in 0..<frameCount {
    while !video.isReadyForMoreMediaData { usleep(1_000) }
    guard let pool = pixels.pixelBufferPool else { fail("no pixel buffer pool") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { fail("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )
    // A slow zoom in, centered: the still at the start, 8% closer at the end.
    let scale = 1 + 0.08 * Double(frame) / Double(frameCount - 1)
    let drawn = CGSize(width: Double(width) * scale, height: Double(height) * scale)
    context?.draw(image, in: CGRect(x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2,
                                    width: drawn.width, height: drawn.height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    pixels.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
}
video.markAsFinished()

let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fail("\(String(describing: writer.error))") }
print("Wrote \(stillURL.lastPathComponent) and \(clipURL.lastPathComponent), content identifier \(identifier)")
