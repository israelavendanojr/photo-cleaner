import AVFoundation
import VideoToolbox

/// Re-encodes a video once, as HEVC with AAC sound, with `CompressionSettings`. The trim is applied
/// while the source is read (`AVAssetReader.timeRange`), so a trimmed and compressed copy is still a
/// single encode. The video keeps its orientation (`preferredTransform`); HDR is read at 10 bits and
/// written as HEVC Main10 with the source's color tags, so it stays HDR. Used for the bin's exports and
/// the level previews alike.
enum VideoEncoder {
    /// Writes `asset`'s `range` (all of it when nil) to `url` as a QuickTime movie. `progress` goes from 0
    /// to 1. Throws `CancellationError` when the task is cancelled, and leaves a partial file behind for
    /// the caller to remove.
    static func encode(_ asset: AVAsset, range: TrimRange?, settings: CompressionSettings, to url: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw VideoEditError.exportFailed }
        let transform = try await video.load(.preferredTransform)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let audioFormat = try await audio?.load(.formatDescriptions).first.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let duration = try await asset.load(.duration)
        let timeRange = range.map {
            CMTimeRange(start: CMTime(seconds: $0.start, preferredTimescale: 600), end: CMTime(seconds: $0.end, preferredTimescale: 600))
        } ?? CMTimeRange(start: .zero, duration: duration)

        let job = try EncodeJob(asset: asset, video: video, transform: transform, audio: audio, audioFormat: audioFormat,
                                timeRange: timeRange, settings: settings, url: url)
        try await withTaskCancellationHandler {
            try await job.run(progress: progress)
        } onCancel: {
            job.cancel()
        }
        try Task.checkCancellation()
    }
}

/// One encode's reader and writer. Each input is fed on its own serial queue; the reader and writer
/// are only touched from those queues, `run` and `cancel`, which AVFoundation allows. `state` orders
/// starting and cancelling: a reader cancelled before it starts must never be started (AVFoundation
/// raises an exception), and one started must be cancelled for real.
private final class EncodeJob: @unchecked Sendable {
    private enum State { case ready, reading, cancelled }
    private let lock = NSLock()
    private var state = State.ready

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderTrackOutput
    private let videoInput: AVAssetWriterInput
    private let audioOutput: AVAssetReaderTrackOutput?
    private let audioInput: AVAssetWriterInput?
    private let timeRange: CMTimeRange

    init(asset: AVAsset, video: AVAssetTrack, transform: CGAffineTransform, audio: AVAssetTrack?,
         audioFormat: AudioStreamBasicDescription?, timeRange: CMTimeRange, settings: CompressionSettings, url: URL) throws {
        self.timeRange = timeRange
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = false

        // 10-bit buffers for HDR, so nothing is lost on the way to Main10.
        let pixelFormat = settings.isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoEditError.exportFailed }
        reader.add(videoOutput)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate,
            AVVideoProfileLevelKey: settings.isHDR ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel,
        ]
        if settings.frameRate > 0 { compression[AVVideoExpectedSourceFrameRateKey] = settings.frameRate }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            // The size keeps the source's aspect ratio, so filling it neither crops nor letterboxes.
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if let color = settings.color {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: color.primaries,
                AVVideoTransferFunctionKey: color.transferFunction,
                AVVideoYCbCrMatrixKey: color.matrix,
            ]
        }
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else { throw VideoEditError.exportFailed }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw VideoEditError.exportFailed }
        writer.add(videoInput)

        if let audio, let audioFormat, let bitrate = settings.audioBitrate {
            // AAC carries up to stereo here, at up to 48 kHz; the reader mixes and resamples to match.
            let channels = min(max(Int(audioFormat.mChannelsPerFrame), 1), 2)
            let sampleRate = min(audioFormat.mSampleRate > 0 ? audioFormat.mSampleRate : 44_100, 48_000)
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
            let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
            let pcm: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVChannelLayoutKey: layoutData,
            ]
            var aac: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVChannelLayoutKey: layoutData,
                AVEncoderBitRateKey: bitrate,
            ]
            // A bitrate the encoder won't take for this rate and layout falls back to its own choice.
            if !writer.canApply(outputSettings: aac, forMediaType: .audio) { aac[AVEncoderBitRateKey] = nil }
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: pcm)
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            } else {
                audioOutput = nil
                audioInput = nil
            }
        } else {
            audioOutput = nil
            audioInput = nil
        }
    }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws {
        let started: Bool? = lock.withLock {
            guard state == .ready else { return nil }
            guard reader.startReading() else { return false }
            state = .reading
            return true
        }
        guard let started else { throw CancellationError() }
        guard started else { throw reader.error ?? VideoEditError.exportFailed }
        guard writer.startWriting() else {
            cancel()
            throw writer.error ?? VideoEditError.exportFailed
        }
        writer.startSession(atSourceTime: timeRange.start)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pump(.video, progress: progress) }
            if audioInput != nil { group.addTask { await self.pump(.audio, progress: nil) } }
        }

        let isCancelled = lock.withLock { state == .cancelled }
        if isCancelled || reader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            if isCancelled { throw CancellationError() }
            throw writer.error ?? reader.error ?? VideoEditError.exportFailed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoEditError.exportFailed }
        progress(1)
    }

    func cancel() {
        lock.withLock {
            if state == .reading { reader.cancelReading() }
            state = .cancelled
        }
    }

    private enum Track { case video, audio }

    /// Feeds one track until the reader runs out (or is cancelled), then marks its input finished.
    private func pump(_ track: Track, progress: (@Sendable (Double) -> Void)?) async {
        let queue = DispatchQueue(label: "com.israelavendanojr.photo-swiper.encode.\(track)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let input = track == .video ? videoInput : audioInput else { return continuation.resume() }
            input.requestMediaDataWhenReady(on: queue) { [self] in
                if feed(track, progress: progress) { continuation.resume() }
            }
        }
    }

    /// Appends `track`'s samples while its input takes them. True once the track is finished, after
    /// which AVFoundation stops asking.
    private func feed(_ track: Track, progress: (@Sendable (Double) -> Void)?) -> Bool {
        let (output, input) = track == .video ? (videoOutput, videoInput) : (audioOutput, audioInput)
        guard let output, let input else { return true }
        while input.isReadyForMoreMediaData {
            guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                input.markAsFinished()
                return true
            }
            if let progress {
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                progress(min(max((time - timeRange.start.seconds) / max(timeRange.duration.seconds, 0.001), 0), 1))
            }
        }
        return false
    }
}
