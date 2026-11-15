import AVFoundation
import Foundation
import Testing
@testable import photo_swiper

/// `VideoEncoder` on the bundled sample clip (H.264, no sound): one pass gives HEVC at the level's size,
/// trimmed while reading. PhotoKit's side of an export (download, save, albums) needs a device.
struct VideoEncoderTests {
    private func sample() throws -> AVURLAsset {
        AVURLAsset(url: try #require(Bundle.main.url(forResource: "mock-video", withExtension: "mp4")))
    }

    private func output() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "encoder-test-\(UUID().uuidString).mov")
    }

    private func settings(for asset: AVAsset) async throws -> CompressionSettings {
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, rate) = try await track.load(.naturalSize, .estimatedDataRate)
        let source = VideoSourceInfo(naturalSize: size, videoBitrate: Int(rate), audioBitrate: nil, frameRate: 30, isHDR: false, color: nil)
        // A long edge below the clip's, so the encode scales.
        var levels = CompressionLevels.standard
        levels.max.maxLongEdge = Int(max(size.width, size.height) / 2)
        return CompressionSettings.resolve(.max, levels: levels, source: source)
    }

    @Test func oneEncodeTrimsAndScalesToHEVC() async throws {
        let asset = try sample()
        let settings = try await settings(for: asset)
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }

        try await VideoEncoder.encode(asset, range: TrimRange(start: 1, end: 3), settings: settings, to: url) { _ in }

        let copy = AVURLAsset(url: url)
        let track = try #require(try await copy.loadTracks(withMediaType: .video).first)
        let (size, formats) = try await track.load(.naturalSize, .formatDescriptions)
        #expect(Int(size.width) == settings.width && Int(size.height) == settings.height)
        #expect(formats.first.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_HEVC)
        let seconds = try await copy.load(.duration).seconds
        #expect(abs(seconds - 2) < 0.15, "Only the trimmed part: \(seconds) s")
    }

    @Test func progressReachesTheEnd() async throws {
        let asset = try sample()
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }
        let last = LastValue()

        try await VideoEncoder.encode(asset, range: nil, settings: try await settings(for: asset), to: url) { last.set($0) }

        #expect(last.value == 1)
    }

    @Test func aCancelledEncodeThrows() async throws {
        let asset = try sample()
        let settings = try await settings(for: asset)
        let url = output()
        defer { try? FileManager.default.removeItem(at: url) }

        let task = Task { try await VideoEncoder.encode(asset, range: nil, settings: settings, to: url) { _ in } }
        task.cancel()

        await #expect(throws: (any Error).self) { try await task.value }
    }
}

private final class LastValue: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Double?
    var value: Double? { lock.withLock { stored } }
    func set(_ value: Double) { lock.withLock { stored = value } }
}
