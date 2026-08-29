import Foundation
import Ollin
import simd

/// The phone held as a pointer: where it is in the room, which way it points, and
/// what the thumb is doing on the screen (Wand mode, rear camera).
///
/// Every other thing the phone sends describes the room. This one describes the
/// person holding it. The phone tracks its own place with plain world tracking, so
/// any ARKit phone can be a wand, and the screen under the thumb is the button.
///
/// `ray` is what a sketch usually wants: it starts at the phone and runs out of
/// the back of it, so pointing the rear camera at a thing is pointing at it.
///
/// ```swift
/// if let wand = device.latestWand, wand.isTracked {
///     for (i, ball) in balls.enumerated() {
///         if wand.ray.hit(sphereAt: ball, radius: 0.1) != nil { held = i }
///     }
///     drawLine(wand.position, wand.point(at: 2))
/// }
/// ```
///
/// `placement` is the frame to draw the phone itself in: x across the screen, y up
/// the screen, and z out of the screen toward the holder, so the pointing
/// direction is **-z**, the way a camera looks in Ollin's own 3D. If a drawing
/// stands on its side, the hold's quarter turn is the number to look at, and
/// `quarterTurns` reports the one the phone sent.
public struct PhoneWand: Sendable {

    /// Whether the phone is tracking the room right now. While this is false the
    /// place and the direction are worth nothing, though the button still works.
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// The camera pose in ARKit world space, exactly as ARKit reports it. Its axes
    /// are fixed to the landscape sensor whatever the hold; use `placement` for the
    /// upright frame.
    public let transform: simd_float4x4

    /// How many quarter turns clockwise stood the camera's axes upright for the
    /// hold. Portrait is 1.
    public let quarterTurns: Int

    /// The frame to draw in: the origin at the phone, x across the screen, y up the
    /// screen, z out of the screen toward the holder. Orthonormal, so
    /// `transform(_:)` never scales what you draw through it.
    public let placement: simd_float4x4

    /// Where the phone is, in ARKit world space (meters).
    public let position: Vector3

    /// Whether a finger is on the screen right now.
    public let isPressed: Bool

    /// How many presses have happened since the app started. It rises by one as
    /// each finger lands and never falls, so a sketch that keeps the number from
    /// last frame sees a tap even if the finger came and went between two draws.
    public let pressCount: Int

    /// Where the thumb sits on the screen, or `nil` while nothing touches it: -1 to
    /// 1 across, -1 to 1 up, the middle at zero. A held press that slides is the
    /// second control a wand gets for free.
    public let touch: Vector2?

    /// Wrap a decoded wire sample. Public so a wand can be staged with no phone (a
    /// test or a figure builds a `PhoneWandSample` and reads it back through the
    /// same accessors the live stream uses).
    public init(_ sample: PhoneWandSample) {
        isTracked = sample.tracked
        timestamp = sample.timestamp
        transform = sample.transform
        quarterTurns = Int(sample.quarterTurnsCW % 4)
        isPressed = sample.pressed
        pressCount = Int(sample.pressCount)
        touch = sample.hasTouch
            ? Vector2(Double(sample.touch.x), Double(sample.touch.y))
            : nil

        // Stand the landscape axes upright for the hold, then hand back a clean
        // frame. ARKit's camera pose carries no scale, so the lengths are there to
        // keep `pointing` a unit vector whatever arrives, and a degenerate matrix
        // falls back to the world axes rather than dividing by zero.
        let held = PhoneWire.wandFrame(fromCamera: sample.transform,
                                       quarterTurnsCW: sample.quarterTurnsCW)
        let lengths = SIMD3<Float>(simd_length(SIMD3(held.columns.0.x, held.columns.0.y, held.columns.0.z)),
                                   simd_length(SIMD3(held.columns.1.x, held.columns.1.y, held.columns.1.z)),
                                   simd_length(SIMD3(held.columns.2.x, held.columns.2.y, held.columns.2.z)))
        let usable = lengths.min() > 1e-6
        let ax = usable ? SIMD3(held.columns.0.x, held.columns.0.y, held.columns.0.z) / lengths.x
                        : SIMD3<Float>(1, 0, 0)
        let ay = usable ? SIMD3(held.columns.1.x, held.columns.1.y, held.columns.1.z) / lengths.y
                        : SIMD3<Float>(0, 1, 0)
        let az = usable ? SIMD3(held.columns.2.x, held.columns.2.y, held.columns.2.z) / lengths.z
                        : SIMD3<Float>(0, 0, 1)
        let origin = SIMD3(held.columns.3.x, held.columns.3.y, held.columns.3.z)
        placement = simd_float4x4(SIMD4(ax, 0), SIMD4(ay, 0), SIMD4(az, 0), SIMD4(origin, 1))
        position = Vector3(Double(origin.x), Double(origin.y), Double(origin.z))
    }

    /// Which way the phone points, in world space: out of the back of it, where the
    /// rear camera looks. A unit vector.
    public var pointing: Vector3 { -direction(placement.columns.2) }

    /// Which way is up the screen, in world space.
    public var up: Vector3 { direction(placement.columns.1) }

    /// Which way is right across the screen, in world space.
    public var across: Vector3 { direction(placement.columns.0) }

    /// The line out of the phone: it starts at the phone and runs the way it
    /// points. Ask it what it hits.
    public var ray: Ray3 { Ray3(origin: position, direction: pointing) }

    /// The point `distance` meters out in front of the phone.
    public func point(at distance: Double) -> Vector3 { position + pointing * distance }

    private func direction(_ column: SIMD4<Float>) -> Vector3 {
        Vector3(Double(column.x), Double(column.y), Double(column.z))
    }
}
