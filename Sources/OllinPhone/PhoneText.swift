import Ollin
import simd

/// One line of text streamed from the phone: what it says, how sure the reader
/// is, and where the line sits (Text mode, rear camera). The reading runs on the
/// phone's own Neural Engine, so the Mac receives finished lines.
///
/// The line's four corners are upright 2D image points, already turned for how
/// the phone was held: map them onto the canvas with `corners(in:)` or
/// `bounds(in:)`, passing the rectangle you want the picture's frame to fill. On
/// a LiDAR phone the corners also carry metric 3D positions in ARKit world space
/// (meters, y up, the origin where the phone's session started), the same world
/// the depth sweep, the room, and the hands stand in, so a sign keeps its place
/// in that scene. `worldTransform` composes them into a ready-made frame: the
/// origin at the line's center, x along the reading direction, y up the line,
/// z out of the surface it sits on.
///
/// ```swift
/// for line in device.latestTexts {
///     drawText(line.text, at: line.bounds(in: bounds).center)
///     if let placement = line.worldTransform {
///         withState { transform(placement); drawBox(size: 0.02) }
///     }
/// }
/// ```
public struct PhoneText: Sendable {

    /// Whether the phone's ARKit session had steady tracking when this line was
    /// read; the world corners of a frame without tracking are best skipped.
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// The recognized text of this line.
    public let text: String

    /// The reader's confidence in the transcription, `0…1`.
    public let confidence: Double

    /// Upright normalized image corners, perimeter order (tl, tr, br, bl).
    private let imageCorners: [SIMD2<Float>]

    /// Metric world-space corners in the same order, or empty when not lifted.
    private let world: [SIMD3<Float>]

    /// Wrap a decoded wire sample. Public so a line can be staged with no phone
    /// (a test or a figure builds a `PhoneTextSample` and reads it back through
    /// the same accessors the live stream uses).
    public init(_ sample: PhoneTextSample) {
        isTracked = sample.isTracked
        timestamp = sample.timestamp
        text = sample.text
        confidence = Double(sample.confidence)
        // The wire guarantees four corners; pad defensively so the accessors
        // never index past a malformed record.
        var corners = sample.corners
        while corners.count < 4 { corners.append(.zero) }
        imageCorners = Array(corners.prefix(4))
        world = sample.hasWorldCorners && sample.worldCorners.count == 4
            ? sample.worldCorners : []
    }

    // MARK: The flat picture

    /// The four corners of the line mapped into `rect` (canvas space), perimeter
    /// order: top-left, top-right, bottom-right, bottom-left. Map into the same
    /// rectangle you draw the scene into and the overlay lines up whichever way
    /// the phone is held.
    public func corners(in rect: Rectangle) -> [Vector2] {
        imageCorners.map { PhoneText.mapped($0, in: rect) }
    }

    /// The axis-aligned box around the line, mapped into `rect`.
    public func bounds(in rect: Rectangle) -> Rectangle {
        let c = corners(in: rect)
        let xs = c.map(\.x), ys = c.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return Rectangle(x: minX, y: minY,
                         width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    /// How much of the picture the line's quad covers, `0…1` (the shoelace area
    /// of the normalized corners): what `latestText` ranks by.
    var imageArea: Double {
        var sum: Float = 0
        for i in 0..<4 {
            let a = imageCorners[i], b = imageCorners[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return Double(abs(sum)) / 2
    }

    // MARK: The world

    /// Whether the corners lifted to metric 3D: `false` on a phone with no LiDAR,
    /// where the line is a flat overlay only.
    public var hasWorldPlacement: Bool { !world.isEmpty }

    /// The four corners in ARKit world space (meters), perimeter order (tl, tr,
    /// br, bl), or empty when the line did not lift.
    public var worldCorners: [Vector3] {
        world.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    /// The center of the line's quad in ARKit world space, or the origin when
    /// the line did not lift.
    public var worldCenter: Vector3 {
        guard !world.isEmpty else { return .zero }
        var sum = SIMD3<Float>.zero
        for c in world { sum += c }
        let c = sum / 4
        return Vector3(Double(c.x), Double(c.y), Double(c.z))
    }

    /// How wide the line runs in the world, in meters (top and bottom edges
    /// averaged), or `0` when the line did not lift.
    public var worldWidth: Double {
        guard !world.isEmpty else { return 0 }
        let top = simd_distance(world[1], world[0])
        let bottom = simd_distance(world[2], world[3])
        return Double(top + bottom) / 2
    }

    /// How tall the line stands in the world, in meters (left and right edges
    /// averaged), or `0` when the line did not lift.
    public var worldHeight: Double {
        guard !world.isEmpty else { return 0 }
        let left = simd_distance(world[0], world[3])
        let right = simd_distance(world[1], world[2])
        return Double(left + right) / 2
    }

    /// The line's frame in ARKit world space, ready for `transform(_:)`: the
    /// origin at the quad's center, x along the reading direction, y up the
    /// line, z out of the surface the text sits on (toward whoever can read it).
    /// `nil` when the line did not lift, or its quad is too degenerate to give
    /// directions.
    public var worldTransform: simd_float4x4? {
        guard world.count == 4 else { return nil }
        // The reading direction and the up-the-line direction, each averaged
        // over its two edges so a slightly skewed quad still gives a frame.
        let across = (world[1] - world[0] + world[2] - world[3]) / 2
        let up = (world[0] - world[3] + world[1] - world[2]) / 2
        let out = simd_cross(across, up)
        guard simd_length(across) > 1e-6, simd_length(out) > 1e-6 else { return nil }
        let x = simd_normalize(across)
        let z = simd_normalize(out)
        let y = simd_cross(z, x)
        var sum = SIMD3<Float>.zero
        for c in world { sum += c }
        let center = sum / 4
        return simd_float4x4(SIMD4<Float>(x, 0), SIMD4<Float>(y, 0),
                             SIMD4<Float>(z, 0), SIMD4<Float>(center, 1))
    }

    /// An upright normalized point (lower-left origin, y up) into canvas space
    /// (top-left origin, y down), scaled into `rect`.
    private static func mapped(_ p: SIMD2<Float>, in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + Double(p.x) * rect.width,
                rect.y + (1 - Double(p.y)) * rect.height)
    }
}
