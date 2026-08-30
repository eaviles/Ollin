import Foundation
import Ollin
import simd

/// A picture or an object the phone knows, found in the room: what it is, where it
/// stands, and how big it really is (Markers mode, rear camera). The phone holds a
/// library of reference files and does the finding on its own Neural Engine, so the
/// Mac receives finished placements.
///
/// `placement` is the matrix a sketch draws through. Its origin sits at the middle
/// of the thing, x runs across its width, y up its height, and z out of the face a
/// reader looks at. Hand it to `transform(_:)` and draw in the marker's own space:
/// the picture is the x-y plane at z = 0, and anything with a positive z stands off
/// the paper toward the viewer. `width` and `height` are meters, so a rectangle of
/// that size covers the print exactly.
///
/// ```swift
/// for marker in device.latestMarkers where marker.isTracked {
///     withState {
///         transform(marker.placement)
///         drawBox(width: marker.width, height: marker.height, depth: 0.002)
///         translate(0, 0, 0.06)
///         drawBox(size: 0.1)
///     }
/// }
/// ```
///
/// A picture is followed while it stays in view, so `isTracked` goes off when it
/// leaves and the last placement stands still. An object is found once and then
/// stays where it was found: it does not follow a thing somebody picks up.
public struct PhoneMarker: Sendable {

    /// The reference's name, which is its file's own name with the extension and
    /// the stated size taken off: `poster@30cm.png` is the marker `poster`.
    public let name: String

    /// Whether this is a flat picture or a scanned solid object.
    public let kind: PhoneMarkerKind

    /// Whether the phone is following this marker right now. A picture that leaves
    /// the view reports `false` and keeps its last placement.
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// The anchor's own id, stable for as long as the phone holds this find.
    public let id: UUID

    /// The anchor's own matrix in ARKit world space, exactly as ARKit reports it. A
    /// picture's anchor lies flat in this frame's x-z plane; use `placement` for the
    /// upright frame most sketches want.
    public let transform: simd_float4x4

    /// What ARKit makes of the size the file name stated: 1.1 means the print in the
    /// room is a tenth bigger than the name said. `width` and `height` already carry
    /// this, so a sketch rarely reads it.
    public let scaleFactor: Double

    /// The measured size of the picture or object, in meters. A picture's `z` is 0.
    public let size: Vector3

    /// The middle of the thing, in ARKit world space (meters).
    public let position: Vector3

    /// The frame to draw in: the origin at `position`, x across the width, y up the
    /// height, z out of the face. Orthonormal, so `transform(_:)` never scales what
    /// you draw through it.
    public let placement: simd_float4x4

    /// Wrap a decoded wire sample. Public so a marker can be staged with no phone (a
    /// test or a figure builds a `PhoneMarkerSample` and reads it back through the
    /// same accessors the live stream uses).
    public init(_ sample: PhoneMarkerSample) {
        name = sample.name
        kind = sample.kind
        isTracked = sample.isTracked
        timestamp = sample.timestamp
        id = sample.id
        transform = sample.transform
        scaleFactor = Double(sample.scaleFactor)

        // ARKit may fold the estimated scale into the anchor itself, so take the
        // basis apart, measure it, and hand back a clean frame with the scale
        // reported as size instead. A degenerate matrix falls back to the world
        // axes rather than dividing by zero.
        let raw = sample.transform
        let lengths = SIMD3<Float>(simd_length(SIMD3(raw.columns.0.x, raw.columns.0.y, raw.columns.0.z)),
                                   simd_length(SIMD3(raw.columns.1.x, raw.columns.1.y, raw.columns.1.z)),
                                   simd_length(SIMD3(raw.columns.2.x, raw.columns.2.y, raw.columns.2.z)))
        let usable = lengths.min() > 1e-6
        let ax = usable ? SIMD3(raw.columns.0.x, raw.columns.0.y, raw.columns.0.z) / lengths.x
                        : SIMD3<Float>(1, 0, 0)
        let ay = usable ? SIMD3(raw.columns.1.x, raw.columns.1.y, raw.columns.1.z) / lengths.y
                        : SIMD3<Float>(0, 1, 0)
        let az = usable ? SIMD3(raw.columns.2.x, raw.columns.2.y, raw.columns.2.z) / lengths.z
                        : SIMD3<Float>(0, 0, 1)
        let origin = SIMD3(raw.columns.3.x, raw.columns.3.y, raw.columns.3.z)

        // A picture lies flat in the anchor's x-z plane with the anchor's y pointing
        // out of the printed face, so the upright frame turns a quarter: the picture
        // runs up -z and looks along +y. A solid object keeps the axes its scan gave
        // it, and its anchor sits at the origin the scanner chose, so the middle of
        // its box is one offset away.
        let scale = Double(sample.scaleFactor)
        switch sample.kind {
        case .image:
            size = Vector3(Double(sample.size.x) * scale, Double(sample.size.y) * scale, 0)
            position = Vector3(Double(origin.x), Double(origin.y), Double(origin.z))
            placement = simd_float4x4(SIMD4(ax, 0), SIMD4(-az, 0), SIMD4(ay, 0), SIMD4(origin, 1))
        case .object:
            size = Vector3(Double(sample.size.x), Double(sample.size.y), Double(sample.size.z))
            let middle = origin + ax * sample.center.x + ay * sample.center.y + az * sample.center.z
            position = Vector3(Double(middle.x), Double(middle.y), Double(middle.z))
            placement = simd_float4x4(SIMD4(ax, 0), SIMD4(ay, 0), SIMD4(az, 0), SIMD4(middle, 1))
        }
    }

    /// Whether this marker is a flat picture.
    public var isImage: Bool { kind == .image }

    /// Whether this marker is a scanned solid object.
    public var isObject: Bool { kind == .object }

    /// How wide the thing is, in meters (a picture's printed width).
    public var width: Double { size.x }

    /// How tall the thing is, in meters.
    public var height: Double { size.y }

    /// How deep the thing is, in meters. A picture reports 0.
    public var depth: Double { size.z }

    /// The direction out of a picture's printed face, in world space. An object
    /// reports the way its own front pointed when somebody scanned it.
    public var facing: Vector3 { direction(placement.columns.2) }

    /// Which way is up the picture, in world space.
    public var up: Vector3 { direction(placement.columns.1) }

    /// Which way the width runs, in world space.
    public var across: Vector3 { direction(placement.columns.0) }

    /// The four corners of a picture in world space, perimeter order: top-left,
    /// top-right, bottom-right, bottom-left. An object reports the four corners of
    /// the slice through the middle of its box, so an outline still reads.
    public var corners: [Vector3] {
        let x = across * (width / 2), y = up * (height / 2)
        return [position - x + y, position + x + y, position + x - y, position - x - y]
    }

    private func direction(_ column: SIMD4<Float>) -> Vector3 {
        Vector3(Double(column.x), Double(column.y), Double(column.z))
    }
}
