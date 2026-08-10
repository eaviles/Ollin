import Foundation
import Ollin

/// What one game controller is doing this frame.
///
/// A snapshot, not a live handle: reading `controller` takes the pad's state
/// once per frame and hands back the numbers, the way `mouseX` hands back a
/// position rather than an object that keeps changing under you. Read it fresh
/// in `draw()`.
///
/// ```swift
/// override func draw() {
///     background(.white)
///     position += controller.leftStick * 6
///     if controller.wasPressed(.a) { drop(at: position) }
///     drawCircle(position, radius: 40)
/// }
/// ```
///
/// ## When nothing is plugged in
///
/// A controller that is not there still answers. Sticks read centered,
/// triggers read 0, no button is down, and `isConnected` is `false`. So a
/// sketch runs with no pad attached and does nothing in particular, rather
/// than needing a check at every call site. Ask `isConnected` when it matters,
/// usually to tell someone to plug one in.
///
/// ## Which way is up
///
/// The sticks are reported in canvas terms: pushing up gives a **negative** y,
/// because Ollin's y grows downward from the top-left. So `position +=
/// controller.leftStick * speed` moves up the screen when the stick goes up,
/// with no sign to remember. The system's own convention is the other way
/// round; this is flipped once, here, so it never has to be flipped in a
/// sketch.
public struct Controller: Sendable, Equatable {

    /// Which player this is, counting from 1. A controller keeps its number
    /// for as long as it stays connected, and a new one takes the lowest free
    /// number, so player 1 does not become player 2 when player 2 leaves.
    public let player: Int

    /// Whether a controller is attached in this slot.
    public let isConnected: Bool

    /// Whether it arrived this frame, for a sketch that wants to greet it.
    public let didConnect: Bool

    /// Whether it left this frame.
    public let didDisconnect: Bool

    /// What the controller calls itself, such as `"DualShock 4"`, or `nil`
    /// when the slot is empty.
    public let name: String?

    /// The left stick, centered at zero, reaching 1 in each direction. Up is
    /// negative y, matching the canvas.
    public let leftStick: Vector2

    /// The right stick, on the same terms.
    public let rightStick: Vector2

    /// The dpad as a direction, each axis −1, 0 or 1. Up is negative y.
    public let dpad: Vector2

    /// How far the left trigger is pulled, 0 to 1. An analog trigger reports
    /// the whole way; a switch-like one jumps.
    public let leftTrigger: Double

    /// How far the right trigger is pulled, 0 to 1.
    public let rightTrigger: Double

    /// Whether this controller reports motion, and has been asked to.
    ///
    /// Two things have to be true: the hardware has the sensors (PlayStation
    /// and Switch controllers do, Xbox controllers do not), and the sketch
    /// called `controllerMotion(true)`, since the sensors cost battery and
    /// stay off until asked.
    public let hasMotion: Bool

    /// How fast the controller is turning, in radians per second about each
    /// axis. Zero without motion.
    public let rotationRate: Vector3

    /// Which way is down, as seen by the controller: a unit-ish vector
    /// pointing along gravity, so it says how the pad is being held. Zero
    /// without motion.
    public let gravity: Vector3

    /// How hard the controller is being moved, gravity already taken out, in
    /// g. Zero without motion.
    public let acceleration: Vector3

    /// Whether this controller has a touchpad. PlayStation controllers do.
    public let hasTouchpad: Bool

    /// Where the finger is on the touchpad, each axis −1 to 1, centered. Up is
    /// negative y. Holds its last position while nothing is touching, so check
    /// `isTouching` before reading it.
    public let touch: Vector2

    /// Whether a finger is on the touchpad now.
    public let isTouching: Bool

    /// How much charge is left, 0 to 1, or `nil` where the controller does not
    /// say (a wired pad usually does not).
    public let batteryLevel: Double?

    /// Whether it is charging.
    public let isCharging: Bool

    let down: ControllerButtonMask
    let pressed: ControllerButtonMask
    let released: ControllerButtonMask

    /// Whether a button is held down right now.
    public func isDown(_ button: ControllerButton) -> Bool { down[button] }

    /// Whether a button went down this frame. True for exactly one frame per
    /// press, so it is the one to use for anything that should happen once.
    public func wasPressed(_ button: ControllerButton) -> Bool { pressed[button] }

    /// Whether a button came up this frame.
    public func wasReleased(_ button: ControllerButton) -> Bool { released[button] }

    /// Whether any button at all is held, for a "press anything to start".
    public var anyButtonIsDown: Bool { !down.isEmpty }

    /// Whether any button went down this frame.
    public var anyButtonWasPressed: Bool { !pressed.isEmpty }

    /// Why this slot is reading nothing, when there is a reason worth saying:
    /// an export, which has no live input, names itself here. An empty slot
    /// with nothing else wrong reads `nil`, since "no controller is plugged
    /// in" is not a fault.
    public let unavailableReason: String?

    /// The empty slot: everything centered, nothing pressed.
    static func absent(player: Int, reason: String? = nil) -> Controller {
        Controller(
            player: player, isConnected: false, didConnect: false, didDisconnect: false,
            name: nil, leftStick: .zero, rightStick: .zero, dpad: .zero,
            leftTrigger: 0, rightTrigger: 0,
            hasMotion: false, rotationRate: .zero, gravity: .zero, acceleration: .zero,
            hasTouchpad: false, touch: .zero, isTouching: false,
            batteryLevel: nil, isCharging: false,
            down: .none, pressed: .none, released: .none,
            unavailableReason: reason)
    }
}
