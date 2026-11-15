import AVFoundation

extension VideoSourceInfo {
    /// The tracks' sizes, bitrates and color. A track that doesn't report its bitrate is worked out from
    /// the file's size and length.
    static func load(from asset: AVAsset, fallbackBytes: Int64) async throws -> VideoSourceInfo {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.exportFailed }
        let (naturalSize, dataRate, frameRate, formats, characteristics) = try await video.load(
            .naturalSize, .estimatedDataRate, .nominalFrameRate, .formatDescriptions, .mediaCharacteristics
        )
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        var audioRate: Int?
        if let audio { audioRate = Int(try await audio.load(.estimatedDataRate)) }
        let duration = try await asset.load(.duration).seconds

        var videoBitrate = Int(dataRate)
        if videoBitrate <= 0, duration > 0 {
            videoBitrate = max(Int(Double(fallbackBytes) * 8 / duration) - (audioRate ?? 0), 1)
        }
        let color = formats.first.flatMap { format -> VideoColor? in
            func tag(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(format, extensionKey: key) as? String }
            guard let primaries = tag(kCMFormatDescriptionExtension_ColorPrimaries),
                  let transfer = tag(kCMFormatDescriptionExtension_TransferFunction),
                  let matrix = tag(kCMFormatDescriptionExtension_YCbCrMatrix) else { return nil }
            return VideoColor(primaries: primaries, transferFunction: transfer, matrix: matrix)
        }
        return VideoSourceInfo(naturalSize: naturalSize, videoBitrate: videoBitrate, audioBitrate: audioRate,
                               frameRate: Double(frameRate), isHDR: characteristics.contains(.containsHDRVideo), color: color)
    }
}
