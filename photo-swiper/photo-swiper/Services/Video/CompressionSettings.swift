import CoreGraphics
import Foundation

/// The compression levels' settings, in one place so they can be tuned. Starting points from JUN-50;
/// estimates and real sizes are logged on each export (`PhotoKitVideoEditor`) to tune them against.
struct CompressionLevels: Equatable, Sendable {
    struct Level: Equatable, Sendable {
        /// The longest side, in pixels. Nil keeps the source's.
        var maxLongEdge: Int?
        var videoBitrate: Bitrate
    }

    enum Bitrate: Equatable, Sendable {
        /// A share of the source's video bitrate, e.g. 0.6.
        case fractionOfSource(Double)
        /// Bits per second.
        case fixed(Int)
    }

    var light = Level(maxLongEdge: nil, videoBitrate: .fractionOfSource(0.6))
    var balanced = Level(maxLongEdge: 1920, videoBitrate: .fixed(6_000_000))
    var max = Level(maxLongEdge: 1280, videoBitrate: .fixed(2_500_000))
    /// AAC, bits per second. Never more than the source's.
    var audioBitrate = 128_000
    /// A level that saves less than this share of the size after trimming is "Already small".
    var alreadySmallFraction = 0.10

    static let standard = CompressionLevels()

    subscript(level: CompressionLevel) -> Level {
        switch level {
        case .light: light
        case .balanced: balanced
        case .max: max
        }
    }
}

/// What the encoder needs to know about a video, read from its tracks. Pure data, so the level rules
/// are tested without AVFoundation.
struct VideoSourceInfo: Equatable, Sendable {
    /// The video track's encoded size, before `preferredTransform` rotates it for display.
    var naturalSize: CGSize
    /// Bits per second.
    var videoBitrate: Int
    /// Bits per second; nil when the video has no sound, 0 when the track doesn't say.
    var audioBitrate: Int?
    var frameRate: Double
    /// HDR video stays HDR: HEVC Main10, with these color tags.
    var isHDR: Bool
    var color: VideoColor?
}

/// A video's color tags, as the `AVVideoColorPropertiesKey` strings (the same values Core Media uses).
struct VideoColor: Equatable, Sendable {
    var primaries: String
    var transferFunction: String
    var matrix: String
}

/// One level's encoder settings for one video: the level's targets, never above the source.
struct CompressionSettings: Equatable, Sendable {
    /// Even, as the encoder needs, in the source's orientation; `preferredTransform` is copied as is.
    var width: Int
    var height: Int
    var videoBitrate: Int
    /// Nil when there's no audio track.
    var audioBitrate: Int?
    var frameRate: Double
    var isHDR: Bool
    var color: VideoColor?

    /// `level`'s settings for `source`. The size keeps the source's aspect ratio and is never larger;
    /// the bitrates are never higher than the source's.
    static func resolve(_ level: CompressionLevel, levels: CompressionLevels, source: VideoSourceInfo) -> CompressionSettings {
        let target = levels[level]
        let longEdge = Swift.max(source.naturalSize.width, source.naturalSize.height)
        let scale = target.maxLongEdge.map { longEdge > 0 ? Swift.min(1, CGFloat($0) / longEdge) : 1 } ?? 1
        let videoBitrate = switch target.videoBitrate {
        case .fractionOfSource(let fraction): Int((Double(source.videoBitrate) * Swift.min(Swift.max(fraction, 0), 1)).rounded())
        case .fixed(let bitrate): Swift.min(bitrate, source.videoBitrate)
        }
        // A source track that doesn't report its bitrate gets the level's.
        let audioBitrate = source.audioBitrate.map { $0 > 0 ? Swift.min(levels.audioBitrate, $0) : levels.audioBitrate }
        return CompressionSettings(
            width: even(source.naturalSize.width * scale), height: even(source.naturalSize.height * scale),
            videoBitrate: Swift.max(videoBitrate, 1), audioBitrate: audioBitrate,
            frameRate: source.frameRate, isHDR: source.isHDR, color: source.color
        )
    }

    /// The copy's size for `seconds` of video: (video + audio bitrate) × length.
    func estimatedBytes(seconds: TimeInterval) -> Int64 {
        Int64((Double(videoBitrate + (audioBitrate ?? 0)) * Swift.max(seconds, 0) / 8).rounded())
    }

    private static func even(_ value: CGFloat) -> Int {
        Swift.max(Int((value / 2).rounded()) * 2, 2)
    }
}

/// What a level would make of a video, for the level popup and the bin.
struct CompressionEstimate: Equatable, Sendable {
    /// The size after trimming, before compressing.
    var trimmedBytes: Int64
    var compressedBytes: Int64
    /// It saves less than `CompressionLevels.alreadySmallFraction` of `trimmedBytes`, so it isn't offered.
    var isAlreadySmall: Bool

    /// `level` applied to `source`, of which `edit` keeps a part. `originalBytes` is the whole video's size.
    static func make(_ level: CompressionLevel, levels: CompressionLevels, source: VideoSourceInfo,
                     originalBytes: Int64, edit: PendingEdit) -> CompressionEstimate {
        let trimmed = PendingEdit(range: edit.range, originalDuration: edit.originalDuration).estimatedBytes(from: originalBytes)
        let settings = CompressionSettings.resolve(level, levels: levels, source: source)
        let compressed = Swift.min(settings.estimatedBytes(seconds: edit.newDuration), trimmed)
        let saved = Double(trimmed - compressed)
        return CompressionEstimate(trimmedBytes: trimmed, compressedBytes: compressed,
                                   isAlreadySmall: saved < Double(trimmed) * levels.alreadySmallFraction)
    }
}
