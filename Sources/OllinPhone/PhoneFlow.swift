import Foundation
import CoreGraphics
import ImageIO
import simd
import Ollin

/// How the phone's picture is moving, everywhere at once (Flow mode, rear
/// camera): a dense field of motion vectors between two consecutive camera
/// frames, measured on the phone and read on the Mac the way the Mac's own
/// optical-flow tracker is read. `field` is a `MotionField`, the same value
/// that tracker produces, and the reads are forwarded here so a sketch written
/// against `flow.field` reads `device.latestFlow` unchanged:
///
/// ```swift
/// if let motion = device.latestFlow {
///     for s in motion.samples(in: rect, every: 36) {
///         drawLine(s.position, s.position + s.flow * 3)
///     }
///     let push = motion.vector(at: particle, in: rect)
/// }
/// ```
///
/// The vectors are how far the picture moved between the two frames, in canvas
/// points once mapped through the rectangle you draw the frame into. `interval`
/// is the time between those two frames, so a displacement divided by it is a
/// speed; the Mac's tracker cannot say that, since its analysis interval
/// breathes with load, but the phone measured both frames and knows. Motion is
/// only measurable where the picture has texture, so a flat wall reads as noise
/// rather than as stillness, the same caveat the Mac's field carries.
///
/// The phone measures camera-native and the Mac stands the map upright for how
/// the phone was held, turning the grid and every vector in it by the same
/// quarter turns; the color frame it was measured on is `PhoneDevice.latestFlowFrame`,
/// stood up the same way, so the two line up in one rectangle.
public struct PhoneFlow: Sendable {

    /// Whether the phone's ARKit session had steady tracking when this reading
    /// was made.
    public let isTracked: Bool

    /// The capture timestamp of the newer of the two frames, in the phone's
    /// clock (seconds).
    public let timestamp: Double

    /// The time between the two frames the motion was measured across, in
    /// seconds. A vector divided by it is a speed in canvas points per second.
    public let interval: Double

    /// The motion field itself, the same `MotionField` the Mac's optical-flow
    /// tracker produces, for a helper written against either.
    public let field: MotionField

    /// Wrap a decoded wire sample. Public so a reading can be staged with no
    /// phone (a test or a figure builds a `PhoneFlowSample` and reads it back
    /// through the same accessors the live stream uses). A map whose stated
    /// size outruns its vectors reads as no motion anywhere.
    public init(_ sample: PhoneFlowSample) {
        self.init(plane: PhoneFlowPlane.upright(sample) ?? .empty,
                  isTracked: sample.isTracked, timestamp: sample.timestamp,
                  interval: sample.interval, confidence: Double(sample.confidence))
    }

    init(plane: PhoneFlowPlane, isTracked: Bool, timestamp: Double,
         interval: Double, confidence: Double) {
        self.isTracked = isTracked
        self.timestamp = timestamp
        self.interval = interval
        self.field = MotionField(width: plane.width, height: plane.height,
                                 confidence: min(max(confidence, 0), 1)) { point in
            plane.flowNormalized(at: point)
        }
    }

    /// How confident the phone is in this field as a whole, `0…1`.
    public var confidence: Double { field.confidence }

    /// The upright flow map's resolution in pixels (coarse on purpose: the
    /// wire's cost is the grid's size, and a query interpolates between cells).
    public var size: Vector2 { field.size }

    /// The average motion across the whole frame in normalized units (`0…1`
    /// of the frame, lower-left origin so +y is up): the global drift. Most
    /// sketches want `averageFlow(in:)`.
    public var averageFlowNormalized: Vector2 { field.averageFlowNormalized }

    /// The motion under `point` (a canvas point inside `rect`, the rectangle you
    /// drew the frame into), as a canvas-space vector: how far the picture under
    /// that point moved between the two frames, in canvas points. Set
    /// `mirrored` when the frame is drawn flipped left-to-right.
    public func vector(at point: Vector2, in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        field.vector(at: point, in: rect, mirrored: mirrored)
    }

    /// The average motion across the whole frame mapped into `rect`, the global
    /// drift as a canvas-space vector.
    public func averageFlow(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        field.averageFlow(in: rect, mirrored: mirrored)
    }

    /// The field sampled on a regular grid covering `rect` (one sample every
    /// `step` canvas points, centered in its cell), ready to draw as arrows.
    public func samples(in rect: Rectangle, every step: Double = 24,
                        mirrored: Bool = false) -> [MotionField.Sample] {
        field.samples(in: rect, every: step, mirrored: mirrored)
    }

    /// The motion at a normalized point (`0…1`, lower-left origin), in the same
    /// normalized units (+y up): the raw surface. Out-of-range points clamp to
    /// the frame edge.
    public func flowNormalized(at point: Vector2) -> Vector2 {
        field.flowNormalized(at: point)
    }
}

/// The upright motion map: `width × height` vectors, row-major from the
/// top-left of the upright picture, each the motion of the picture at that cell
/// in flow-map pixels (x right, y down). Built once per reading off the wire
/// (turned upright there), then read by every query through a bilinear lookup.
struct PhoneFlowPlane: Sendable {
    let width: Int
    let height: Int
    let vectors: [SIMD2<Float>]

    static let empty = PhoneFlowPlane(width: 0, height: 0, vectors: [])

    /// Stand a camera-native sample upright by its own turn count: the grid
    /// turns, and so does every vector in it, by the same quarter turns
    /// clockwise. `nil` when the stated size outruns the vectors, so a
    /// malformed record can never index past the plane.
    static func upright(_ sample: PhoneFlowSample) -> PhoneFlowPlane? {
        let w = sample.flowWidth, h = sample.flowHeight
        guard w > 0, h > 0, sample.flow.count >= w * h else { return nil }
        let source = sample.flow
        switch sample.orientation % 4 {
        case 1:
            // A quarter turn clockwise: the top row becomes the right column.
            // A vector pointing right in the old picture points down in the new.
            var out = [SIMD2<Float>](repeating: .zero, count: w * h)
            for y in 0..<w {
                for x in 0..<h {
                    let v = source[(h - 1 - x) * w + y]
                    out[y * h + x] = SIMD2<Float>(-v.y, v.x)
                }
            }
            return PhoneFlowPlane(width: h, height: w, vectors: out)
        case 2:
            var out = [SIMD2<Float>](repeating: .zero, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    out[y * w + x] = -source[(h - 1 - y) * w + (w - 1 - x)]
                }
            }
            return PhoneFlowPlane(width: w, height: h, vectors: out)
        case 3:
            // A quarter turn counterclockwise: the top row becomes the left
            // column, read bottom to top; right turns into up.
            var out = [SIMD2<Float>](repeating: .zero, count: w * h)
            for y in 0..<w {
                for x in 0..<h {
                    let v = source[x * w + (w - 1 - y)]
                    out[y * h + x] = SIMD2<Float>(v.y, -v.x)
                }
            }
            return PhoneFlowPlane(width: h, height: w, vectors: out)
        default:
            return PhoneFlowPlane(width: w, height: h, vectors: Array(source.prefix(w * h)))
        }
    }

    /// The motion at a normalized point (`0…1`, lower-left origin), in
    /// normalized units of the picture with +y up: a bilinear read between the
    /// four nearest cells, clamped at the edges. The map's rows run from the
    /// top of the picture down, so the query's y turns over here, and so does
    /// the answer's.
    func flowNormalized(at point: Vector2) -> Vector2 {
        guard width > 0, height > 0 else { return .zero }
        let fx = min(max(point.x, 0), 1) * Double(width) - 0.5
        let fy = min(max(1 - point.y, 0), 1) * Double(height) - 0.5
        let x0 = min(max(Int(fx.rounded(.down)), 0), width - 1)
        let y0 = min(max(Int(fy.rounded(.down)), 0), height - 1)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(min(max(fx - Double(x0), 0), 1))
        let ty = Float(min(max(fy - Double(y0), 0), 1))
        let top = vectors[y0 * width + x0] * (1 - tx) + vectors[y0 * width + x1] * tx
        let bottom = vectors[y1 * width + x0] * (1 - tx) + vectors[y1 * width + x1] * tx
        let v = top * (1 - ty) + bottom * ty
        return Vector2(Double(v.x) / Double(width), -Double(v.y) / Double(height))
    }
}

/// One decoded flow reading, boxed for the hand-off from the reader thread to
/// the main thread. The map is stood upright and the color JPEG decoded here
/// (the heavy parts); the drawable frame `Image` is built lazily on the main
/// actor when the sketch reads it. `@unchecked Sendable`: the CGImage is
/// freshly created by the decode and handed over whole, and the rest is value.
struct PhoneFlowBox: @unchecked Sendable {
    let sequence: Int
    let reading: PhoneFlow
    let orientation: UInt8
    let color: CGImage?         // sensor orientation; nil when none was sent
}

/// Decode a `PhoneFlowSample` into a boxed reading: stand the map upright,
/// JPEG-decode the color, and build the field once. Returns `nil` if the map
/// is empty or too short for its stated size (the last good reading then stays
/// put on the Mac).
///
/// Free function (not a method) so the reader thread calls it without
/// main-actor isolation.
func decodePhoneFlow(_ sample: PhoneFlowSample, sequence: Int) -> PhoneFlowBox? {
    guard let plane = PhoneFlowPlane.upright(sample) else { return nil }
    var color: CGImage?
    if !sample.colorJPEG.isEmpty,
       let source = CGImageSourceCreateWithData(sample.colorJPEG as CFData, nil) {
        color = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    let reading = PhoneFlow(plane: plane, isTracked: sample.isTracked,
                            timestamp: sample.timestamp, interval: sample.interval,
                            confidence: Double(sample.confidence))
    return PhoneFlowBox(sequence: sequence, reading: reading,
                        orientation: sample.orientation, color: color)
}
