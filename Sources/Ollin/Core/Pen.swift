import Foundation

/// The stylus: how it is being held, and which end of it is down.
///
/// A tablet reports more about a pen than where it is. How hard it is pressed
/// arrives as ``Sketch/pressure``, which a Force Touch trackpad sends too, and
/// the rest of it is here: how far the pen is leaning, how far its barrel has
/// been turned, and whether the end on the tablet is the eraser.
///
/// ```swift
/// override func draw() {
///     guard mouseIsPressed else { return }
///     // A nib that follows the lean: wide across the direction of the tilt.
///     strokeWeight(2 + pressure * 10 + pen.tilt.length * 8)
///     stroke(pen.isEraser ? Color(white: 1) : .black)
///     drawLine(previousMouse, mouse)
/// }
/// ```
///
/// Everything here is zero, and `isNearby` false, on a machine with no tablet,
/// so a sketch written against a pen still runs under a mouse; read
/// `tiltIsAvailable` to offer something else there.
public struct Pen: Sendable, Equatable, Codable {

    /// How far the pen is leaning, `-1...1` on each axis: `.zero` when it is
    /// straight up, and `x` positive when the top of the pen leans right, `y`
    /// positive when it leans down the canvas. Its length is how far from
    /// upright the pen is, near 1 when it is almost flat on the tablet.
    public var tilt: Vector2

    /// How far the pen's barrel has been turned, in radians, `0..<2π`. Only an
    /// art pen reports this; every other stylus leaves it at 0.
    public var twist: Double

    /// Whether the end on the tablet is the eraser rather than the tip.
    public var isEraser: Bool

    /// Whether a stylus is over the tablet at all, which it is while hovering
    /// as well as while drawing. A pen lifted away from the tablet turns this
    /// false and leaves the rest as it was.
    public var isNearby: Bool

    /// Whether the device sending pointer events reports a lean at all. Like
    /// ``Sketch/pressureIsAvailable`` the answer comes from the events rather
    /// than from the machine, so it is false until a pen has been used.
    public var tiltIsAvailable: Bool

    public init(tilt: Vector2 = .zero, twist: Double = 0, isEraser: Bool = false,
                isNearby: Bool = false, tiltIsAvailable: Bool = false) {
        self.tilt = Vector2(min(max(tilt.x, -1), 1), min(max(tilt.y, -1), 1))
        self.twist = Pen.wrapped(twist)
        self.isEraser = isEraser
        self.isNearby = isNearby
        self.tiltIsAvailable = tiltIsAvailable
    }

    /// A turn folded into one lap, so a barrel turned past a full circle reads
    /// as where it points rather than as how far it has been.
    static func wrapped(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        let lap = 2 * Double.pi
        let folded = radians.truncatingRemainder(dividingBy: lap)
        return folded < 0 ? folded + lap : folded
    }
}
