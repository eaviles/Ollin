import Ollin
import Vision
import CoreGraphics
import Foundation
import os

/// One saliency result: the heat map and the regions it peaks in, from a still
/// image. The live path publishes the same surfaces as properties on
/// `SaliencyTracker`.
///
/// `@unchecked Sendable`: `Image` is a class, but the heat map is freshly created
/// by the detector and handed over whole — nothing else holds or mutates it.
public struct Saliency: @unchecked Sendable {

    /// The heat map as a drawable `Image` — white, alpha = salience (`0…1`).
    /// At the model's own coarse resolution (68×68, whatever the source's size
    /// or aspect); drawing it into the source's rectangle stretches it smoothly
    /// onto the picture, and `tint(_:)` recolors it into a glow, a fog, a
    /// spotlight.
    public let heatMap: Image

    /// The most salient regions as bounding quads (usually a handful at most),
    /// strongest coverage of where the heat concentrates.
    public let regions: [DetectedRectangle]

    let observation: SaliencyImageObservation

    /// The salience under `point` (a canvas point inside `rect`, the rectangle
    /// you drew the source into), `0…1`. Out-of-range points clamp to the edge.
    public func salience(at point: Vector2, in rect: Rectangle,
                         mirrored: Bool = false) -> Double {
        let normalized = VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored)
        return SaliencyTracker.salienceNormalized(observation, at: normalized)
    }

    /// The salience at a normalized point (`0…1`, lower-left origin) — the raw
    /// surface, for when you're working in Vision's coordinate space yourself.
    public func salienceNormalized(at point: Vector2) -> Double {
        SaliencyTracker.salienceNormalized(observation, at: point)
    }
}

/// Maps what draws the eye in a camera's frames (or a still image): a coarse
/// heat map of visual salience plus the bounding regions it peaks in. Unlike the
/// segmenters, which answer "which pixels are the subject," this answers "which
/// parts of the picture matter" — for any content.
///
/// ```swift
/// let camera = Camera()
/// lazy var saliency = SaliencyTracker(camera)
/// override func draw() {
///     let rect = camera.fittedRectangle(in: bounds) ?? bounds
///     if let frame = camera.frame { drawImage(frame, in: rect) }
///     if let heat = saliency.heatMap {
///         tint(Color(red: 1, green: 0.6, blue: 0.1, alpha: 0.7))
///         drawImage(heat, in: rect)   // attention as a warm glow
///         noTint()
///     }
/// }
/// ```
///
/// Two flavors via `mode`: `.attention` (the default) predicts where a person's
/// eye goes — trained on human gaze, drawn to faces and contrast — while
/// `.objectness` highlights regions likely to contain discrete objects, whether
/// or not they draw the eye. `heatMap` is a white-alpha image like the
/// segmentation matte (`tint(_:)` recolors it), `regions` the salient bounding
/// boxes, and `salience(at:in:)` reads the value under any canvas point — a
/// density field for stippling, an attractor for particles. It's a neural
/// model, so it needs a capable compute device (Apple silicon); on a Mac
/// without one `isAvailable` turns `false` and `unavailableReason` says why.
public final class SaliencyTracker: VisionTracking, @unchecked Sendable {

    /// Which kind of salience the model maps.
    public enum Mode: Sendable {
        /// Where a person's eye is drawn — trained on human gaze.
        case attention
        /// Where discrete objects likely are, whether or not they draw the eye.
        case objectness
    }

    /// Which kind of salience this tracker maps (fixed at init; make one tracker
    /// per mode to read both).
    public let mode: Mode

    /// Published results plus whether the heat-map image surface has been read.
    /// The observation and regions are kept always (storing them is free; every
    /// `salience` query reads the observation directly), but the heat-map byte
    /// conversion runs on the analyzer thread only once a read has armed it.
    private struct State {
        var heatMap: Image?
        var regions: [DetectedRectangle] = []
        var observation: SaliencyImageObservation?
        var wantsHeatMap = false
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("saliency")

    /// The heat map from the most recent analyzed frame — white, alpha =
    /// salience — or `nil` before the first result. The first read arms the
    /// conversion, so it can stay `nil` until the next analyzed frame publishes.
    public var heatMap: Image? {
        lock.withLockUnchecked { state in
            state.wantsHeatMap = true
            return state.heatMap
        }
    }

    /// The most salient regions in the most recent analyzed frame, as bounding
    /// quads (usually a handful at most; empty when nothing stands out, or
    /// before the first result).
    public var regions: [DetectedRectangle] { lock.withLockUnchecked { $0.regions } }

    /// Whether saliency can run on this Mac. Some Macs lack the compute device
    /// (Neural Engine) the model needs; when so, this is `false` and
    /// `unavailableReason` says why instead of just reporting an empty map.
    public var isAvailable: Bool { status.isAvailable }
    /// Why saliency can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Map salience over `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource, mode: Mode = .attention) {
        self.mode = mode
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// The salience under `point` (a canvas point inside `rect`, the rectangle
    /// you drew the frame into), `0…1`, from the most recent analyzed frame —
    /// `0` before the first result. Out-of-range points clamp to the edge. Set
    /// `mirrored` when the frame is drawn flipped left-to-right (the selfie
    /// orientation).
    public func salience(at point: Vector2, in rect: Rectangle,
                         mirrored: Bool = false) -> Double {
        guard let observation = lock.withLockUnchecked({ $0.observation }) else { return 0 }
        let normalized = VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored)
        return Self.salienceNormalized(observation, at: normalized)
    }

    /// The salience at a normalized point (`0…1`, lower-left origin) — the raw
    /// surface. Most sketches want `salience(at:in:)`, which queries and answers
    /// in canvas space.
    public func salienceNormalized(at point: Vector2) -> Double {
        guard let observation = lock.withLockUnchecked({ $0.observation }) else { return 0 }
        return Self.salienceNormalized(observation, at: point)
    }

    /// Map the salience of a still image, once. `nil` only if the heat map
    /// couldn't be converted.
    public static func detect(in image: Image, mode: Mode = .attention) async throws -> Saliency? {
        let observation = try await perform(mode, on: image.currentCGImage())
        guard let matteGray = try? observation.heatMap.cgImage,
              let heatMap = SegmentationImages.matteImage(from: matteGray) else { return nil }
        return Saliency(heatMap: heatMap,
                        regions: observation.salientObjects.map(DetectedRectangle.init),
                        observation: observation)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable on this Mac, stop calling perform —
        // it won't recover this session, and re-trying every frame just wastes
        // work and lets Vision log its own error per frame.
        guard status.isAvailable else { return }
        do {
            let observation = try await Self.perform(mode, on: cgImage)
            status.recordSuccess()
            // Convert the heat-map image only once some read has armed it; the
            // observation and regions always publish (queries read them directly).
            let wantsHeatMap = lock.withLockUnchecked { $0.wantsHeatMap }
            var heatMap: Image?
            if wantsHeatMap, let matteGray = try? observation.heatMap.cgImage {
                heatMap = SegmentationImages.matteImage(from: matteGray)
            }
            let regions = observation.salientObjects.map(DetectedRectangle.init)
            lock.withLockUnchecked { state in
                state.observation = observation
                state.regions = regions
                if wantsHeatMap { state.heatMap = heatMap }
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Helpers

    private static func perform(_ mode: Mode, on cgImage: CGImage) async throws -> SaliencyImageObservation {
        switch mode {
        case .attention:  return try await GenerateAttentionBasedSaliencyImageRequest().perform(on: cgImage)
        case .objectness: return try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: cgImage)
        }
    }

    /// The heat-map value at a normalized point (lower-left origin), clamped to
    /// the map. Two facts about Vision's lookup, both pinned empirically:
    /// `pixel(at:)` indexes the buffer **top-down** — it takes row/column
    /// fractions, not a point in Vision's usual lower-left normalized space —
    /// so the y flips here (a real bug: queries used to read the vertically
    /// mirrored spot, hidden by the vertically-centered test fixture); and it's
    /// nearest-neighbor with no bounds clamping of its own (the optical-flow
    /// lesson: a coordinate that rounds past the last pixel traps), so clamp to
    /// the last pixel's exact coordinate before querying.
    static func salienceNormalized(_ observation: SaliencyImageObservation,
                                   at point: Vector2) -> Double {
        let heat = observation.heatMap
        let w = Double(heat.size.width)
        let h = Double(heat.size.height)
        guard w > 0, h > 0 else { return 0 }
        let query = NormalizedPoint(x: min(max(point.x, 0), (w - 1) / w),
                                    y: min(max(1 - point.y, 0), (h - 1) / h))
        return Double(heat.pixel(at: query))
    }
}
