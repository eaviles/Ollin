import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
import VideoToolbox
import os
import Ollin

/// Reads a recording's video one frame at a time, by frame number.
///
/// The satellite decodes its own video (a satellite cannot lean on another).
/// The decode is one sequential pass that holds the frame it is on and the one
/// after it, which is what playing forward asks for and costs no seek. A
/// request the pass has already left behind, or one far ahead of it, starts a
/// new pass a little before the frame and rolls forward to it, so any frame is
/// exact at the price of a few spare decodes.
///
/// The frames come out as the sensor delivered them. `uprightBuffer(at:)` is
/// the same frame turned to stand the way the phone was held.
@MainActor
final class PhoneRecordingVideo {

    /// When each frame is shown, in seconds from the first, in order.
    let times: [Double]
    /// The picture's size as the sensor delivered it.
    let width: Int
    let height: Int

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let quarterTurnsCW: Int

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: (index: Int, buffer: CVPixelBuffer)?
    private var lookahead: (index: Int, buffer: CVPixelBuffer)?

    private var turner: PictureTurner?
    private var upright: (index: Int, buffer: CVPixelBuffer)?

    private var textureCache: CVMetalTextureCache?
    private var inFlightTextures: [CVMetalTexture] = []
    private lazy var ciContext = CIContext()

    /// How far ahead of the pass a request may be before a new pass is cheaper
    /// than rolling forward to it.
    private static let maxRoll = 90

    /// Opens the video and reads when each of its frames is shown, without
    /// decoding any of them. `nil` when the file has no video track to read.
    init?(url: URL, quarterTurnsCW: Int) {
        let asset = AVURLAsset(url: url)
        let loaded = Self.loadBlocking(asset)
        guard let track = loaded.track, let size = loaded.size, !loaded.times.isEmpty else { return nil }
        self.asset = asset
        self.track = track
        self.times = loaded.times
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
        self.quarterTurnsCW = ((quarterTurnsCW % 4) + 4) % 4
    }

    // MARK: Frames

    /// The decoded frame `index`, as the sensor delivered it, or `nil` when the
    /// video cannot produce it.
    func buffer(at index: Int) -> CVPixelBuffer? {
        guard times.indices.contains(index) else { return nil }
        if let current, current.index == index { return current.buffer }
        if let found = roll(to: index, from: restartPoint(for: index)) { return found }
        // The pass opened past the frame (a range boundary the reader rounded
        // its own way): start from the top and roll all the way.
        return roll(to: index, from: 0)
    }

    /// The same frame turned upright for how the phone was held.
    func uprightBuffer(at index: Int) -> CVPixelBuffer? {
        guard let source = buffer(at: index) else { return nil }
        guard quarterTurnsCW != 0 else { return source }
        if let upright, upright.index == index { return upright.buffer }
        guard let turned = turn(source) else { return nil }
        upright = (index, turned)
        return turned
    }

    /// A decoded frame wrapped as a Metal texture the image pipeline samples
    /// in linear light. A fresh texture each call, never one written in place,
    /// since a frame still on its way to the screen may be reading the last.
    func image(from buffer: CVPixelBuffer) -> Image? {
        if textureCache == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            textureCache = cache
        }
        guard let cache = textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, buffer, nil, .bgra8Unorm_srgb,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        inFlightTextures.append(cvTexture)
        if inFlightTextures.count > 6 { inFlightTextures.removeFirst() }
        return Image(texture: texture)
    }

    /// A decoded frame as a `CGImage`, for a reader that wants pixels on the
    /// CPU (a vision tracker's tap).
    func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    // MARK: The pass

    /// Where a new pass should open to reach `index`, or `nil` when the pass
    /// that is running can roll forward to it.
    private func restartPoint(for index: Int) -> Int? {
        guard reader != nil, let current else { return index }
        if index < current.index || index > current.index + Self.maxRoll { return index }
        return nil
    }

    private func roll(to index: Int, from start: Int?) -> CVPixelBuffer? {
        if let start { restart(at: start) }
        while let now = current, now.index < index, let next = lookahead {
            current = next
            lookahead = pull()
        }
        guard let current, current.index == index else { return nil }
        return current.buffer
    }

    private func restart(at index: Int) {
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
        // Open a little before the frame; the roll forward lands on it exactly.
        let start = index > 0 ? max(0, times[index] - 0.25) : 0
        if start > 0 {
            newReader.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: PhoneRecordingFile.videoTimeScale),
                duration: .positiveInfinity)
        }
        guard newReader.startReading() else { return }
        reader = newReader
        output = newOutput
        current = pull()
        lookahead = pull()
    }

    /// The next decoded frame of the pass with its number, found from the time
    /// it is shown at, or `nil` at the end of the video.
    private func pull() -> (index: Int, buffer: CVPixelBuffer)? {
        guard let output else { return nil }
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard pts.isValid else { continue }
            return (Self.nearestIndex(to: pts.seconds, in: times), buffer)
        }
        return nil
    }

    /// The frame whose time is nearest `seconds`. The times are in order, so
    /// this is a binary search and a look at one neighbor.
    static func nearestIndex(to seconds: Double, in times: [Double]) -> Int {
        guard !times.isEmpty else { return 0 }
        var low = 0, high = times.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if times[mid] <= seconds { low = mid } else { high = mid - 1 }
        }
        if low + 1 < times.count, abs(times[low + 1] - seconds) < abs(times[low] - seconds) {
            return low + 1
        }
        return low
    }

    // MARK: The turn

    private func turn(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        if turner == nil { turner = PictureTurner(quarterTurnsCW: quarterTurnsCW) }
        guard let turner else { return nil }
        let sideways = quarterTurnsCW % 2 == 1
        let w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source)
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var destination: CVPixelBuffer?
        // A fresh buffer for each turned frame, for the same reason a texture
        // is never rewritten in place.
        guard CVPixelBufferCreate(nil, sideways ? h : w, sideways ? w : h,
                                  kCVPixelFormatType_32BGRA, attributes as CFDictionary,
                                  &destination) == kCVReturnSuccess,
              let destination,
              VTPixelRotationSessionRotateImage(turner.session, source, destination) == noErr
        else { return nil }
        return destination
    }

    // MARK: Opening

    /// AVFoundation's loaders are async-only and a recording opens from a
    /// plain initializer, so the caller waits once while a detached task reads
    /// the track and steps a cursor over its sample table. The cursor reads
    /// the table, never the samples, so a long recording opens quickly.
    private nonisolated static func loadBlocking(
        _ asset: AVURLAsset
    ) -> (track: AVAssetTrack?, size: CGSize?, times: [Double]) {
        let done = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<(AVAssetTrack?, CGSize?, [Double])>(
            uncheckedState: (nil, nil, []))
        Task.detached {
            let track = try? await asset.loadTracks(withMediaType: .video).first
            var size: CGSize?
            var times: [Double] = []
            if let track {
                size = try? await track.load(.naturalSize)
                let hasCursors = (try? await track.load(.canProvideSampleCursors)) ?? false
                times = sampleTimes(of: track, in: asset, hasCursors: hasCursors)
            }
            box.withLockUnchecked { $0 = (track, size, times) }
            done.signal()
        }
        done.wait()
        return box.withLockUnchecked { $0 }
    }

    /// When each sample of the track is shown, in order.
    private nonisolated static func sampleTimes(of track: AVAssetTrack, in asset: AVURLAsset,
                                                hasCursors: Bool) -> [Double] {
        var times: [Double] = []
        if hasCursors,
           let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() {
            repeat {
                let pts = cursor.presentationTimeStamp
                if pts.isValid { times.append(pts.seconds) }
            } while cursor.stepInDecodeOrder(byCount: 1) == 1
        } else if let reader = try? AVAssetReader(asset: asset) {
            // No cursor for this file: read the samples through, undecoded.
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                if reader.startReading() {
                    while let sample = output.copyNextSampleBuffer() {
                        guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                        if pts.isValid { times.append(pts.seconds) }
                    }
                }
            }
        }
        times.sort()
        return times
    }
}

/// Owns the session that turns a frame by quarter turns, and closes it when
/// the video lets go. A class of its own so the closing needs no actor.
private final class PictureTurner {
    let session: VTPixelRotationSession

    init?(quarterTurnsCW: Int) {
        var made: VTPixelRotationSession?
        guard VTPixelRotationSessionCreate(nil, &made) == noErr, let made else { return nil }
        let angle: CFString
        switch quarterTurnsCW {
        case 1: angle = kVTRotation_CW90
        case 2: angle = kVTRotation_180
        default: angle = kVTRotation_CCW90
        }
        VTSessionSetProperty(made, key: kVTPixelRotationPropertyKey_Rotation, value: angle)
        session = made
    }

    deinit { VTPixelRotationSessionInvalidate(session) }
}
