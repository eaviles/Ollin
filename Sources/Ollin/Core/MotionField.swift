import Foundation

/// How a picture is moving, everywhere at once: a dense field of motion
/// vectors between the previous analyzed frame and this one. Sample it
/// anywhere, a grid of arrows, a particle's position, the point under the
/// cursor, and you get the local image motion as a `Vector2` in canvas points.
///
/// The field is dense (one vector per flow-map pixel), so it is not converted
/// up front: each query reads straight out of whatever measured it.
/// `vector(at:in:)` answers in canvas space ("which way is the picture moving
/// under this point"), `samples(in:)` lays a whole grid of them for drawing,
/// and `averageFlowNormalized` is the global drift (a camera pan reads as one
/// shared direction).
///
/// This value lives in the core so every source of motion reports the same
/// thing: the Mac's own optical-flow tracker over a camera or a video, and a
/// tethered iPhone measuring its camera on the phone, read through
/// `PhoneDevice.latestFlow`. A sketch written against one reads the other
/// unchanged, and a helper that takes a `MotionField` takes both.
///
/// A source of its own builds one with `init(width:height:confidence:flowNormalized:)`,
/// handing over the read: a closure from a normalized point (`0…1`, lower-left
/// origin) to the motion there in the same normalized units (+y up).
public struct MotionField: Sendable {

    /// One grid sample from `samples(in:)`: where it was taken, and the local
    /// motion there, both in canvas space.
    public struct Sample: Sendable {
        /// The canvas point the field was sampled at.
        public let position: Vector2
        /// The local motion at `position`, in canvas points: how far the picture
        /// under that point moved since the previous analyzed frame.
        public let flow: Vector2

        public init(position: Vector2, flow: Vector2) {
            self.position = position
            self.flow = flow
        }
    }

    /// The read behind every query: the motion at a normalized point (`0…1`,
    /// lower-left origin), in normalized units (+y up).
    private let read: @Sendable (Vector2) -> Vector2

    /// How confident the tracker is in this field as a whole, `0…1`.
    public let confidence: Double

    /// The average motion across the whole frame, in normalized units (`0…1` of
    /// the frame, lower-left origin so +y is up), the global drift. A camera pan
    /// shows up here as one shared direction; localized motion (a waving hand)
    /// mostly averages out. Most sketches want `averageFlow(in:)` instead.
    public let averageFlowNormalized: Vector2

    /// The flow map's resolution in pixels.
    public let size: Vector2

    /// Wrap a measured field. `width` and `height` are the flow map's own
    /// resolution, and `flowNormalized` reads the motion at a normalized point
    /// (`0…1`, lower-left origin) in the same normalized units, +y up. The read
    /// is called for every query, so it should be a lookup, not a computation;
    /// it is called 144 times here, once per cell of a coarse grid, to settle
    /// the global drift.
    public init(width: Int, height: Int, confidence: Double,
                flowNormalized read: @escaping @Sendable (Vector2) -> Vector2) {
        self.read = read
        self.confidence = confidence
        self.size = Vector2(Double(max(width, 0)), Double(max(height, 0)))

        // The global drift, from a coarse fixed grid, cheap enough (each read is
        // a flow-map lookup) to make the average a plain stored value.
        let grid = 12
        var sum = Vector2.zero
        for j in 0..<grid {
            for i in 0..<grid {
                sum += read(Vector2((Double(i) + 0.5) / Double(grid),
                                    (Double(j) + 0.5) / Double(grid)))
            }
        }
        self.averageFlowNormalized = sum * (1.0 / Double(grid * grid))
    }

    /// The motion at a normalized point (`0…1`, lower-left origin), returned in
    /// the same normalized units (+y up), the raw surface, for when you are
    /// working in that coordinate space yourself. Most sketches want
    /// `vector(at:in:)`, which queries and answers in canvas space. Out-of-range
    /// points clamp to the frame edge.
    public func flowNormalized(at point: Vector2) -> Vector2 {
        read(point)
    }

    /// The motion under `point` (a canvas point inside `rect`, the rectangle you
    /// drew the frame into), as a canvas-space vector: how far the picture under
    /// that point moved since the previous analyzed frame, in canvas points.
    /// Set `mirrored` when the frame is drawn flipped left-to-right (the selfie
    /// orientation): the query lands on the right pixel and the vector's x
    /// flips with the picture.
    public func vector(at point: Vector2, in rect: Rectangle,
                       mirrored: Bool = false) -> Vector2 {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        // Canvas (top-left origin, y down) to normalized (lower-left, y up).
        let u = (point.x - rect.x) / rect.width
        let v = (point.y - rect.y) / rect.height
        let flow = flowNormalized(at: Vector2(mirrored ? 1 - u : u, 1 - v))
        return Vector2((mirrored ? -flow.x : flow.x) * rect.width,
                       -flow.y * rect.height)
    }

    /// The average motion across the whole frame mapped into `rect`, the global
    /// drift as a canvas-space vector. See `averageFlowNormalized`.
    public func averageFlow(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        Vector2((mirrored ? -averageFlowNormalized.x : averageFlowNormalized.x) * rect.width,
                -averageFlowNormalized.y * rect.height)
    }

    /// The field sampled on a regular grid covering `rect` (one sample every
    /// `step` canvas points, centered in its cell), ready to draw as arrows:
    ///
    /// ```swift
    /// for s in field.samples(in: view, every: 36) {
    ///     drawLine(s.position, s.position + s.flow * 3)
    /// }
    /// ```
    public func samples(in rect: Rectangle, every step: Double = 24,
                        mirrored: Bool = false) -> [Sample] {
        guard step > 0, rect.width > 0, rect.height > 0 else { return [] }
        var result: [Sample] = []
        var y = rect.y + step / 2
        while y < rect.y + rect.height {
            var x = rect.x + step / 2
            while x < rect.x + rect.width {
                let position = Vector2(x, y)
                result.append(Sample(position: position,
                                     flow: vector(at: position, in: rect, mirrored: mirrored)))
                x += step
            }
            y += step
        }
        return result
    }
}
