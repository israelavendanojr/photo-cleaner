// Generates the short clip every mock video plays in the preview.
// Usage: swift Tools/generate_mock_video.swift photo-swiper/Resources/mock-video.mp4
// Output is deterministic; re-running overwrites the file.

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

let width = 540
let height = 960
let fps: Int32 = 30
let seconds = 8.0

guard CommandLine.arguments.count == 2 else {
    print("usage: swift generate_mock_video.swift <output.mp4>")
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: url)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: a
    )
}

/// Soft sea at dusk: a sky gradient, a drifting sun, and rolling wave bands. `t` runs 0...1.
func draw(_ ctx: CGContext, t: Double) {
    let w = CGFloat(width), h = CGFloat(height)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let sky = CGGradient(colorsSpace: space, colors: [rgb(0x2E4A6B), rgb(0xE9A27C), rgb(0xF6D3A8)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.4), options: [.drawsAfterEndLocation])

    let sunY = h * (0.52 + 0.08 * t)
    ctx.setFillColor(rgb(0xFFE6B8, 0.9))
    ctx.fillEllipse(in: CGRect(x: w * 0.5 - 70, y: sunY - 70, width: 140, height: 140))

    let bands: [(UInt32, CGFloat)] = [(0x3F6E8C, 0.42), (0x356180, 0.32), (0x2A5270, 0.22), (0x1F4260, 0.11)]
    for (i, band) in bands.enumerated() {
        let phase = t * 2 * .pi * Double(i + 1) * 0.5
        ctx.setFillColor(rgb(band.0))
        ctx.move(to: CGPoint(x: 0, y: 0))
        for x in stride(from: 0, through: Int(w), by: 6) {
            let y = band.1 * h + 14 * CGFloat(sin(Double(x) / 70 + phase + Double(i)))
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: y))
        }
        ctx.addLine(to: CGPoint(x: w, y: 0))
        ctx.closePath()
        ctx.fillPath()
    }

    // A progress tick along the bottom so scrubbing is visibly frame-accurate.
    ctx.setFillColor(rgb(0xFFFDF9, 0.8))
    ctx.fill(CGRect(x: 0, y: 0, width: w * CGFloat(t), height: 6))
}

let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 600_000],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frameCount = Int(seconds * Double(fps))
for frame in 0..<frameCount {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )!
    draw(ctx, t: Double(frame) / Double(frameCount))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else {
    print("failed: \(writer.error?.localizedDescription ?? "unknown")")
    exit(1)
}
print("wrote \(url.path)")
