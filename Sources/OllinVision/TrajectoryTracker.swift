import Ollin
import Vision
import CoreMedia
import CoreVideo
import Foundation
import os

/// The arc of something flying through the scene — a thrown ball, a bounced
/// pebble — as a run of points along a parabola, with where it's headed next.
///
/// Points come back in normalized coordinates; map them to the canvas with the
/// `in:` helpers, passing the same rectangle you drew the frame into.
public struct DetectedTrajectory: Sendable, Identifiable {

    /// A stable identity for this trajectory: the same physical arc keeps the
    /// same `id` across frames as more of it comes into view, so a sketch can
    /// accumulate or age out trails per arc.
    public let id: UUID

    /// How confident the detector is that these points are one real trajectory,
    /// `0…1` — a good value to fade an overlay by.
    public let confidence: Double

    /// The observed centroids, in order of travel — the path so far. Normalized
    /// coordinates (`0…1`, lower-left origin); most sketches want
    /// `detectedPoints(in:)` instead.
    public let detectedPointsNormalized: [Vector2]

    /// The points projected onto the fitted parabola — the smoothed path, and
    /// where the arc is headed. Normalized; see `projectedPoints(in:)`.
    public let projectedPointsNormalized: [Vector2]

    /// The fitted parabola in normalized space (lower-left origin):
    /// `y = coefficients.x · x² + coefficients.y · x + coefficients.z`.
    public let equationCoefficients: SIMD3<Double>

    /// The moving object's radius as a fraction of the frame (a moving average) —
    /// roughly how big the thing tracing this arc is.
    public let normalizedRadius: Double

    /// When the trajectory was observed, in seconds on the tracker's clock
    /// (since the tracker started; frame index over the frame rate for the
    /// offline path), or `nil` when the detector didn't report it.
    public let timeRange: ClosedRange<Double>?

    init(_ observation: TrajectoryObservation) {
        self.id = observation.uuid
        self.confidence = Double(observation.confidence)
        self.detectedPointsNormalized = observation.detectedPoints.map {
            Vector2(Double($0.x), Double($0.y))
        }
        self.projectedPointsNormalized = observation.projectedPoints.map {
            Vector2(Double($0.x), Double($0.y))
        }
        self.equationCoefficients = SIMD3(Double(observation.equationCoefficients.x),
                                          Double(observation.equationCoefficients.y),
                                          Double(observation.equationCoefficients.z))
        self.normalizedRadius = Double(observation.movingAverageRadius)
        if let range = observation.timeRange, range.start.isNumeric, range.end.isNumeric,
           range.end.seconds >= range.start.seconds {
            self.timeRange = range.start.seconds...range.end.seconds
        } else {
            self.timeRange = nil
        }
    }

    /// The observed path mapped into `rect` (canvas space). Set `mirrored` when
    /// the frame is drawn flipped left-to-right (the selfie orientation).
    public func detectedPoints(in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        detectedPointsNormalized.map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The fitted (smoothed) path mapped into `rect`.
    public func projectedPoints(in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        projectedPointsNormalized.map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }
}

/// Detects things flying through a source's frames — each result a parabolic
/// arc of points (a throw, a bounce), found without being told what to look
/// for.
///
/// Where `ObjectTracker` follows a patch you seed it with, this one watches
/// for *ballistic motion* on its own: anything small that moves along a
/// parabola against a steady background gets reported as a `DetectedTrajectory`.
/// The camera must hold still (a moving camera turns the whole scene into
/// motion). It's a classical detector (no neural model), so it runs on any
/// Mac.
///
/// ```swift
/// let camera = Camera()
/// lazy var tracker = TrajectoryTracker(camera)
///
/// override func draw() {
///     guard let frame = camera.frame else { return }
///     let view = camera.fittedRect(in: bounds) ?? bounds
///     drawImage(frame, in: view)
///     for arc in tracker.trajectories {
///         stroke(Color.green.opacity(arc.confidence))
///         drawPolyline(arc.projectedPoints(in: view))
///     }
/// }
/// ```
public final class TrajectoryTracker: VisionTracking, @unchecked Sendable {

    private struct State {
        /// The live request — built and owned on the analysis task, kept between
        /// frames so its internal state accumulates (it needs `trajectoryLength`
        /// observations of an object before it reports an arc).
        var request: DetectTrajectoriesRequest?
        /// The uptime of the first analyzed frame; later frames are timestamped
        /// relative to it.
        var startUptime: TimeInterval?
        /// The last timestamp handed to the request, to keep them strictly
        /// increasing even if two frames land on the same clock tick.
        var lastSeconds: Double = -1
        var result: [DetectedTrajectory] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let status = VisionStatus("trajectory detection")
    private let trajectoryLength: Int
    private let minimumObjectRadius: Double?
    private let maximumObjectRadius: Double?

    /// The trajectories in the most recent analyzed frame — empty while nothing
    /// is flying. An arc keeps its `id` across frames, so accumulate by `id` to
    /// build trails that outlive the detection.
    public var trajectories: [DetectedTrajectory] { lock.withLock { $0.result } }

    /// Whether trajectory detection can run here (it's classical, so effectively
    /// always `true`); `unavailableReason` would explain a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why trajectory detection can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Detect trajectories in `source`'s frames — the live camera, a playing
    /// video, or any frame source.
    ///
    /// `trajectoryLength` is how many observations of an object it takes before
    /// an arc is reported (more = steadier, later). The optional radius bounds
    /// (fractions of the frame, `0…1`) filter what counts as a moving object —
    /// set a maximum to ignore large movers like a person crossing the scene.
    @MainActor
    public init(_ source: any FrameSource, trajectoryLength: Int = 10,
                minimumObjectRadius: Double? = nil, maximumObjectRadius: Double? = nil) {
        self.trajectoryLength = trajectoryLength
        self.minimumObjectRadius = minimumObjectRadius
        self.maximumObjectRadius = maximumObjectRadius
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Forget everything observed so far and start fresh — call after the scene
    /// jumps (a video loop or seek), so a discontinuity isn't read as motion.
    public func reset() {
        lock.withLock { state in
            state.request = nil
            state.startUptime = nil
            state.lastSeconds = -1
            state.result = []
        }
    }

    // MARK: Offline

    /// Detect trajectories across an explicit ordered sequence of frames (at
    /// `frameRate` frames per second), returning the detections per frame. The
    /// camera-free path — find the arcs in a recorded clip's frames, and how
    /// the behavior is tested.
    public static func detect(across images: [Image], frameRate: Double = 30,
                              trajectoryLength: Int = 10) async throws -> [[DetectedTrajectory]] {
        let request = DetectTrajectoriesRequest(trajectoryLength: trajectoryLength)
        var results: [[DetectedTrajectory]] = []
        for (index, image) in images.enumerated() {
            let seconds = Double(index) / frameRate
            guard let sample = sampleBuffer(from: image.currentCGImage(), at: seconds,
                                            frameDuration: 1 / frameRate) else {
                results.append([])
                continue
            }
            let observations = try await request.perform(on: sample)
            results.append(observations.map(DetectedTrajectory.init))
        }
        return results
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }

        let (request, seconds): (DetectTrajectoriesRequest, Double) = lock.withLock { state in
            if state.request == nil {
                let request = DetectTrajectoriesRequest(trajectoryLength: trajectoryLength)
                if let minimumObjectRadius {
                    request.objectMinimumNormalizedRadius = Float(minimumObjectRadius)
                }
                if let maximumObjectRadius {
                    request.objectMaximumNormalizedRadius = Float(maximumObjectRadius)
                }
                state.request = request
                state.startUptime = ProcessInfo.processInfo.systemUptime
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - state.startUptime!
            let seconds = max(elapsed, state.lastSeconds + 0.001)
            state.lastSeconds = seconds
            return (state.request!, seconds)
        }

        // Detection needs to know *when* each frame is: the request only accepts
        // time through a timestamped sample buffer (an untimestamped image
        // silently detects nothing), so the frame is wrapped in one here.
        guard let sample = TrajectoryTracker.sampleBuffer(from: cgImage, at: seconds) else { return }

        do {
            let observations = try await request.perform(on: sample)
            status.recordSuccess()
            lock.withLock { state in
                // A reset mid-flight replaced the request; drop this stale result.
                guard state.request === request else { return }
                state.result = observations.map(DetectedTrajectory.init)
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Frame wrapping

    /// A timestamped sample buffer holding `cgImage`'s pixels — what the
    /// detector requires to relate frames across time.
    static func sampleBuffer(from cgImage: CGImage, at seconds: Double,
                             frameDuration: Double = 1.0 / 30) -> CMSampleBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(nil, cgImage.width, cgImage.height, kCVPixelFormatType_32BGRA,
                            attributes, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0,
                                         width: CGFloat(cgImage.width),
                                         height: CGFloat(cgImage.height)))

        var formatOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatOut)
        guard let format = formatOut else { return nil }

        let timescale: CMTimeScale = 600
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: frameDuration, preferredTimescale: timescale),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: timescale),
            decodeTimeStamp: .invalid)
        var sampleOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                 formatDescription: format, sampleTiming: &timing,
                                                 sampleBufferOut: &sampleOut)
        return sampleOut
    }
}
