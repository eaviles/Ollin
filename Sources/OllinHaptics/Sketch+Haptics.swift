import Foundation
import Ollin

extension Sketch {

    /// Play a pattern now, so the hand feels what the eye is about to see.
    ///
    /// Call it at the moment something happens, not every frame: touch marks
    /// events, the way a drum marks a bar. A pattern played over one already
    /// running joins it, because there is one actuator to share.
    ///
    /// ```swift
    /// override func draw() {
    ///     background(.white)
    ///     if ball.y > floor {
    ///         ball.bounce()
    ///         playHaptic(.tap(intensity: ball.speed / maxSpeed, sharpness: 0.7))
    ///     }
    ///     drawCircle(ball.position, radius: 20)
    /// }
    /// ```
    ///
    /// On a machine with nothing to feel, and in an export, this does nothing
    /// and the sketch runs on.
    public func playHaptic(_ pattern: HapticPattern) {
        HapticHub.shared.play(pattern)
    }

    /// Stop every pattern in flight.
    ///
    /// Worth calling when a sketch changes state under a running hum, so the
    /// old feeling does not outlive what made it.
    public func stopHaptics() {
        HapticHub.shared.stop()
    }

    /// Turn everything felt up or down at once, from 0 (silent) to 1 (as
    /// written).
    ///
    /// This is the volume parameter for touch. Set it in `setup()`, or drive it
    /// from a parameter so the piece can be turned down in a room where it is too
    /// much.
    public func hapticStrength(_ strength: Double) {
        HapticHub.shared.strength = max(0, strength.finiteOrZero)
    }

    /// Whether anything here can be felt.
    public var hapticsAreAvailable: Bool {
        HapticHub.shared.hardware != .none
    }

    /// What is on the other end: a full engine, a trackpad that knocks, or
    /// nothing.
    ///
    /// Read it when a sketch wants to say something different to each. A
    /// trackpad has one strength, so a piece built on strength alone reads
    /// flat there and may want fewer, crisper marks instead.
    public var hapticHardware: HapticHardware {
        HapticHub.shared.hardware
    }

    /// Why nothing can be felt, or nil when something can.
    ///
    /// Written as a sentence a sketch can draw on the canvas.
    public var hapticsUnavailableReason: String? {
        HapticHub.shared.unavailableReason
    }
}
