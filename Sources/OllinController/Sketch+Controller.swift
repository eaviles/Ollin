import Foundation
import GameController
import Ollin

extension Sketch {

    /// What player one's controller is doing this frame.
    ///
    /// Read it fresh in `draw()`, the way you read `mouseX`. With nothing
    /// plugged in it reads centered and unpressed, so a sketch runs either
    /// way.
    ///
    /// ```swift
    /// override func draw() {
    ///     background(.white)
    ///     ship += controller.leftStick * 6
    ///     if controller.wasPressed(.a) { fire(from: ship) }
    ///     drawCircle(ship, radius: 30)
    /// }
    /// ```
    public var controller: Controller {
        ControllerHub.shared.controller(player: 1, frame: frameCount)
    }

    /// What a given player's controller is doing, counting from 1.
    ///
    /// A controller keeps its number while it stays connected, and a new one
    /// takes the lowest free number, so unplugging player 2 does not renumber
    /// player 1. Asking about a player nobody is holds a controller for reads
    /// centered and unpressed, like any empty slot.
    ///
    /// ```swift
    /// for player in 1...4 {
    ///     let pad = controller(player)
    ///     guard pad.isConnected else { continue }
    ///     draw(paddle: player, at: pad.leftStick)
    /// }
    /// ```
    public func controller(_ player: Int) -> Controller {
        ControllerHub.shared.controller(player: player, frame: frameCount)
    }

    /// Every controller attached right now, player one first.
    public var connectedControllers: [Controller] {
        let hub = ControllerHub.shared
        let count = hub.slotCount(frame: frameCount)
        guard count > 0 else { return [] }
        return (1...count)
            .map { hub.controller(player: $0, frame: frameCount) }
            .filter(\.isConnected)
    }

    /// How many controllers are attached.
    public var controllerCount: Int {
        ControllerHub.shared.connectedCount(frame: frameCount)
    }

    /// Ask the controllers for motion, or stop asking.
    ///
    /// Off by default, and worth leaving off unless a sketch reads it: the
    /// sensors draw battery for as long as they are on. Call it in `setup()`.
    ///
    /// Only some hardware has the sensors at all. PlayStation and Switch
    /// controllers do; Xbox controllers do not, and never report motion
    /// however this is set. Check `controller.hasMotion` rather than assuming.
    ///
    /// ```swift
    /// override func setup() { controllerMotion(true) }
    /// override func draw() {
    ///     rotate(controller.gravity.x * 0.5)
    ///     drawRect(center: center, width: 400, height: 40)
    /// }
    /// ```
    public func controllerMotion(_ enabled: Bool) {
        ControllerHub.shared.motionEnabled = enabled
    }

    /// How much of a stick's travel around the center to read as center,
    /// default `0.1`.
    ///
    /// A stick rarely rests at exactly zero, and a worn one rests further off,
    /// so a sketch that adds the stick to a position every frame will drift on
    /// its own with no deadzone at all. The cut is radial and rescaled, so a
    /// stick just past the edge reads near zero and still reaches a full 1
    /// pushed all the way, rather than jumping the moment it escapes.
    ///
    /// Set `0` to read the hardware untouched.
    public func controllerDeadzone(_ amount: Double) {
        ControllerHub.shared.deadzone = max(0, min(amount, 0.9))
    }

    /// Whether to keep reading controllers while another app is in front.
    ///
    /// Off by default, which is the system's own default since macOS 11.3: a
    /// controller feeds whichever app is frontmost, so a sketch behind another
    /// window reads centered and unpressed. Turn it on for an installation, or
    /// for a set where the sketch is projected while a different window is
    /// being typed into.
    public func controllersRunInBackground(_ enabled: Bool) {
        GCController.shouldMonitorBackgroundEvents = enabled
    }

    /// Put the system into pairing mode, so a wireless controller that has
    /// never been paired can be found.
    ///
    /// A controller already paired with this Mac connects on its own and needs
    /// none of this. Pairing is otherwise a System Settings job.
    public func discoverControllers(_ finished: (@Sendable () -> Void)? = nil) {
        GCController.startWirelessControllerDiscovery(completionHandler: finished)
    }
}
