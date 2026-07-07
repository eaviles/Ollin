import AVFoundation
import CoreVideo
import Foundation
import os

/// Decodes a video file frame-by-frame for the headless exporters, where no
/// runloop services a playing `AVPlayer`. Frames are pulled *by timestamp*
/// against the sketch's fixed-timestep clock, so an exported video sketch is
/// deterministic: the same frame number always shows the same video frame.
///
/// The decode is a sequential `AVAssetReader` pass (fast: no per-frame seek),
/// holding the current sample and one look-ahead. Asking for a time the pass
/// already left behind (a loop wrap, a backward `seek`) restarts the reader a
/// little before the target and rolls forward, trading a few spare decodes for
/// exactness at any boundary.
@MainActor
final class HeadlessVideoReader {

    /// The clip duration in seconds, loaded synchronously at init.
    let duration: Double?
    /// The video track's pixel dimensions, loaded synchronously at init.
    let naturalSize: CGSize?

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: (buffer: CVPixelBuffer, start: Double)?
    private var lookahead: (buffer: CVPixelBuffer, start: Double)?

    /// Opens the clip and synchronously loads the video track and metadata.
    /// Returns `nil` when the file has no readable video track.
    init?(url: URL) {
        let asset = AVURLAsset(url: url)
        let loaded = Self.loadBlocking(asset)
        guard let track = loaded.track else { return nil }
        self.asset = asset
        self.track = track
        self.duration = loaded.duration
        self.naturalSize = loaded.size
    }

    /// The decoded frame covering `seconds`, or the nearest one the clip has
    /// (the first frame before it starts, the last frame after it ends).
    func pixelBuffer(at seconds: Double) -> CVPixelBuffer? {
        // A request behind the current sample means the sequential pass has
        // already gone past it: restart slightly earlier and roll forward.
        // (The slack absorbs the reader's own range-boundary behavior.)
        if reader == nil || seconds < (current?.start ?? 0) - 1e-6 {
            restart(at: seconds)
        }
        while let next = lookahead, next.start <= seconds + 1e-9 {
            current = next
            lookahead = pullSample()
        }
        return current?.buffer
    }

    private func restart(at seconds: Double) {
        reader?.cancelReading()
        reader = nil
        output = nil
        current = nil
        lookahead = nil

        guard let newReader = try? AVAssetReader(asset: asset) else { return }
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let newOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        newOutput.alwaysCopiesSampleData = false
        guard newReader.canAdd(newOutput) else { return }
        newReader.add(newOutput)
        let start = max(0, seconds - 0.5)
        if start > 0 {
            newReader.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600), duration: .positiveInfinity)
        }
        guard newReader.startReading() else { return }
        reader = newReader
        output = newOutput
        current = pullSample()
        lookahead = pullSample()
    }

    /// The next decoded sample in presentation order (decompressed track
    /// output delivers display order), or `nil` at the end of the clip.
    private func pullSample() -> (buffer: CVPixelBuffer, start: Double)? {
        guard let output else { return nil }
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            return (buffer, pts.isValid ? pts.seconds : 0)
        }
        return nil
    }

    /// AVFoundation's metadata loaders are async-only, but the export drivers
    /// are synchronous loops, so the reader blocks once at creation; the work
    /// runs on a detached task while the caller waits (a local file loads in
    /// milliseconds).
    private nonisolated static func loadBlocking(
        _ asset: AVURLAsset
    ) -> (track: AVAssetTrack?, duration: Double?, size: CGSize?) {
        let done = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<(AVAssetTrack?, Double?, CGSize?)>(
            uncheckedState: (nil, nil, nil))
        Task.detached {
            let track = try? await asset.loadTracks(withMediaType: .video).first
            let duration = try? await asset.load(.duration)
            let size: CGSize? = if let track { try? await track.load(.naturalSize) } else { nil }
            let seconds: Double? = (duration?.isValid ?? false) ? duration?.seconds : nil
            box.withLockUnchecked { $0 = (track, seconds, size) }
            done.signal()
        }
        done.wait()
        return box.withLockUnchecked { $0 }
    }
}
