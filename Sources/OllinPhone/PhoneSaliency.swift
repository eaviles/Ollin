import Foundation
import CoreGraphics
import ImageIO
import simd
import Ollin

/// One region the phone's attention model picked out: the bounding box of
/// something that draws the eye, with the model's confidence. The box is an
/// upright normalized rectangle, already turned for how the phone was held; map
/// it onto the canvas with `bounds(in:)` or `center(in:)`, passing the rectangle
/// you draw the picture's frame into.
///
/// On a LiDAR phone the region's center also carries a metric 3D position in
/// ARKit world space (meters, y up, the origin where the phone's session
/// started), the same world the depth sweep, the room, and the hands stand in,
/// so the thing being looked at keeps a place in that scene.
public struct PhoneSalientRegion: Sendable {

    /// The model's confidence in the region, `0…1`.
    public let confidence: Double

    /// Upright normalized box, lower-left origin (x, y, width, height).
    private let box: SIMD4<Float>

    /// Metric world-space center, or `nil` when the region did not lift.
    private let world: SIMD3<Float>?

    /// Wrap a decoded wire record. Public so a region can be staged with no phone
    /// (a test or a figure builds a `PhoneSalientRegionSample` and reads it back
    /// through the same accessors the live stream uses).
    public init(_ sample: PhoneSalientRegionSample) {
        confidence = Double(sample.confidence)
        box = SIMD4<Float>(sample.x, sample.y, sample.width, sample.height)
        world = sample.hasWorldCenter ? sample.worldCenter : nil
    }

    /// The region's box mapped into `rect` (canvas space). Map into the same
    /// rectangle you draw the frame into and the box lands on the thing it marks
    /// whichever way the phone is held.
    public func bounds(in rect: Rectangle) -> Rectangle {
        Rectangle(x: rect.x + Double(box.x) * rect.width,
                  y: rect.y + (1 - Double(box.y + box.w)) * rect.height,
                  width: Double(box.z) * rect.width,
                  height: Double(box.w) * rect.height)
    }

    /// The center of the region mapped into `rect` (canvas space).
    public func center(in rect: Rectangle) -> Vector2 {
        bounds(in: rect).center
    }

    /// Whether the region's center lifted to metric 3D: `false` on a phone with
    /// no LiDAR, where the region is a flat overlay only.
    public var hasWorldPlacement: Bool { world != nil }

    /// The region's center in ARKit world space (meters), or the origin when the
    /// region did not lift.
    public var worldCenter: Vector3 {
        guard let world else { return .zero }
        return Vector3(Double(world.x), Double(world.y), Double(world.z))
    }
}

/// One reading of where the phone's picture draws the eye (Attention mode, rear
/// camera): a coarse heat map of visual attention plus the bounding regions it
/// peaks in. The model runs on the phone's own Neural Engine, so the Mac
/// receives a finished map, the same kind the Mac-side saliency tracking
/// computes from a local camera.
///
/// The heat map is coarse on purpose (the model's own resolution, whatever the
/// picture's size): drawn into the frame's rectangle it stretches smoothly onto
/// the picture, and `salience(at:in:)` reads the value under any canvas point,
/// a density field for stippling or an attractor for particles. Read the
/// drawable form from `PhoneDevice.latestSaliencyHeatMap`.
///
/// ```swift
/// if let attention = device.latestSaliency {
///     for region in attention.regions {
///         drawRect(region.bounds(in: rect))
///     }
///     let pull = attention.salience(at: particle.position, in: rect)
/// }
/// ```
public struct PhoneSaliency: Sendable {

    /// Whether the phone's ARKit session had steady tracking when this reading
    /// was made; the world centers of a frame without tracking are best skipped.
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// The most salient regions, strongest coverage of where the heat
    /// concentrates (usually a handful at most; empty when nothing stands out).
    public let regions: [PhoneSalientRegion]

    /// The heat map's pixel size (the model's own coarse resolution).
    public let heatWidth: Int
    public let heatHeight: Int

    /// The heat bytes, row-major from the top-left of the upright picture.
    private let heat: [UInt8]

    /// Wrap a decoded wire sample. Public so a reading can be staged with no
    /// phone (a test or a figure builds a `PhoneSaliencySample` and reads it back
    /// through the same accessors the live stream uses).
    public init(_ sample: PhoneSaliencySample) {
        isTracked = sample.isTracked
        timestamp = sample.timestamp
        regions = sample.regions.map(PhoneSalientRegion.init)
        // Believe the dims only as far as the bytes back them, so a malformed
        // record can never index past the plane.
        if sample.heatWidth > 0, sample.heatHeight > 0,
           sample.heat.count >= sample.heatWidth * sample.heatHeight {
            heatWidth = sample.heatWidth
            heatHeight = sample.heatHeight
            heat = sample.heat
        } else {
            heatWidth = 0
            heatHeight = 0
            heat = []
        }
    }

    /// The region the model is most sure of, or `nil` when nothing stands out.
    public var strongestRegion: PhoneSalientRegion? {
        regions.max { $0.confidence < $1.confidence }
    }

    /// The salience under `point` (a canvas point inside `rect`, the rectangle
    /// you drew the frame into), `0…1`. Out-of-range points clamp to the edge.
    public func salience(at point: Vector2, in rect: Rectangle) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        return salienceNormalized(at: Vector2((point.x - rect.x) / rect.width,
                                              1 - (point.y - rect.y) / rect.height))
    }

    /// The salience at a normalized point (`0…1`, lower-left origin, the
    /// convention the wire's boxes are carried in). The raw surface, for when
    /// you are working in that space yourself; most sketches want
    /// `salience(at:in:)`, which queries and answers in canvas space.
    public func salienceNormalized(at point: Vector2) -> Double {
        guard heatWidth > 0, heatHeight > 0 else { return 0 }
        // The heat rows run from the top of the picture down, so the y turns
        // over here; clamp first, so an out-of-range query reads the edge.
        let col = min(max(Int(point.x * Double(heatWidth)), 0), heatWidth - 1)
        let row = min(max(Int((1 - point.y) * Double(heatHeight)), 0), heatHeight - 1)
        return Double(heat[row * heatWidth + col]) / 255
    }
}

/// One decoded attention reading, boxed for the hand-off from the reader thread
/// to the main thread. The color JPEG is decoded here (it is the heavy part);
/// the drawable heat-map and frame `Image`s are built lazily on the main actor
/// when the sketch reads them. `@unchecked Sendable`: the CGImage is freshly
/// created by the decode and handed over whole, and the sample is a value.
struct PhoneSaliencyBox: @unchecked Sendable {
    let sequence: Int
    let sample: PhoneSaliencySample
    let color: CGImage?         // sensor orientation; nil when none was sent
}

/// Decode a `PhoneSaliencySample` into a boxed reading: JPEG-decode the color
/// and keep the sample beside it. Returns `nil` if the heat map is empty or too
/// short for its stated size (a reading with no usable color still stands; the
/// frame accessor then has nothing to show).
///
/// Free function (not a method) so the reader thread calls it without
/// main-actor isolation.
func decodePhoneSaliency(_ sample: PhoneSaliencySample, sequence: Int) -> PhoneSaliencyBox? {
    guard sample.heatWidth > 0, sample.heatHeight > 0,
          sample.heat.count >= sample.heatWidth * sample.heatHeight else { return nil }
    var color: CGImage?
    if !sample.colorJPEG.isEmpty,
       let source = CGImageSourceCreateWithData(sample.colorJPEG as CFData, nil) {
        color = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    return PhoneSaliencyBox(sequence: sequence, sample: sample, color: color)
}
