import Foundation
import GameController

/// A button on a game controller, named by where it sits rather than by what
/// the hardware prints on it.
///
/// The face buttons are the crux. A controller's own labels differ by make: a
/// PlayStation pad prints cross, circle, square and triangle where an Xbox pad
/// prints A, B, X and Y. The system reports them **by position**, so `.a` is
/// always the bottom face button whatever it is called on the pad in someone's
/// hands, and a sketch written for one controller works on the other. Reach for
/// `.a` meaning "the one under the thumb", not "the one marked A".
///
/// ```
///        (y)              triangle
///     (x)   (b)      square      circle
///        (a)                cross
/// ```
///
/// Not every controller has every button. `.options`, `.home`, the thumbstick
/// clicks and `.touchpad` are all absent on some pads, and a button a
/// controller does not have simply never reads as down.
public enum ControllerButton: String, CaseIterable, Sendable {

    /// The bottom face button: cross on a PlayStation pad, A on an Xbox pad.
    case a
    /// The right face button: circle on a PlayStation pad, B on an Xbox pad.
    case b
    /// The left face button: square on a PlayStation pad, X on an Xbox pad.
    case x
    /// The top face button: triangle on a PlayStation pad, Y on an Xbox pad.
    case y

    /// The upper left bumper.
    case leftShoulder
    /// The upper right bumper.
    case rightShoulder

    /// The left trigger, as a button. Read `leftTrigger` for how far it is
    /// pulled; this is down once it passes the hardware's own threshold.
    case leftTrigger
    /// The right trigger, as a button.
    case rightTrigger

    /// Clicking the left stick in. Absent on some controllers.
    case leftStick
    /// Clicking the right stick in. Absent on some controllers.
    case rightStick

    /// The dpad's up.
    case up
    /// The dpad's down.
    case down
    /// The dpad's left.
    case left
    /// The dpad's right.
    case right

    /// The menu button: options on a PlayStation pad, the burger on an Xbox pad.
    case menu
    /// The secondary system button, where a controller has one: share or
    /// create on a PlayStation pad, view on an Xbox pad.
    case options
    /// The maker's logo button. Some systems reserve this, so it may never
    /// arrive even on a controller that plainly has one.
    case home

    /// Pressing the touchpad in, on a controller that has one.
    case touchpad

    /// The button on the given profile, or `nil` where this controller has
    /// none.
    func input(on pad: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch self {
        case .a: pad.buttonA
        case .b: pad.buttonB
        case .x: pad.buttonX
        case .y: pad.buttonY
        case .leftShoulder: pad.leftShoulder
        case .rightShoulder: pad.rightShoulder
        case .leftTrigger: pad.leftTrigger
        case .rightTrigger: pad.rightTrigger
        case .leftStick: pad.leftThumbstickButton
        case .rightStick: pad.rightThumbstickButton
        case .up: pad.dpad.up
        case .down: pad.dpad.down
        case .left: pad.dpad.left
        case .right: pad.dpad.right
        case .menu: pad.buttonMenu
        case .options: pad.buttonOptions
        case .home: pad.buttonHome
        case .touchpad: (pad as? GCDualShockGamepad)?.touchpadButton
            ?? (pad as? GCDualSenseGamepad)?.touchpadButton
        }
    }
}

/// One bit per button, so a frame's whole button state is a single value to
/// store and to difference.
///
/// A press and a release are found by comparing two frames rather than by
/// asking the system for events, which is what lets a synthetic controller
/// exercise the same code an attached one does.
struct ControllerButtonMask: Equatable, Sendable {

    private var bits: UInt32 = 0

    static let none = ControllerButtonMask()

    private static let index: [ControllerButton: UInt32] = {
        var table: [ControllerButton: UInt32] = [:]
        for (i, button) in ControllerButton.allCases.enumerated() {
            table[button] = UInt32(1) << UInt32(i)
        }
        return table
    }()

    subscript(button: ControllerButton) -> Bool {
        get { bits & (Self.index[button] ?? 0) != 0 }
        set {
            guard let bit = Self.index[button] else { return }
            if newValue { bits |= bit } else { bits &= ~bit }
        }
    }

    /// The buttons down here and not in `other`: the presses since that frame.
    func rising(from other: ControllerButtonMask) -> ControllerButtonMask {
        var mask = ControllerButtonMask()
        mask.bits = bits & ~other.bits
        return mask
    }

    /// The buttons down in `other` and not here: the releases since that frame.
    func falling(from other: ControllerButtonMask) -> ControllerButtonMask {
        var mask = ControllerButtonMask()
        mask.bits = other.bits & ~bits
        return mask
    }

    /// Whether anything at all is down, for `anyButtonIsDown`.
    var isEmpty: Bool { bits == 0 }
}
