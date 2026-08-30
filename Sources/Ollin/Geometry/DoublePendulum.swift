import Foundation

/// A double pendulum: two bobs on rigid arms, the simplest system that moves
/// chaotically. Small swings are orderly; raise the energy and the second bob
/// traces the tangled, never-repeating loops the system is famous for, where
/// two starts a hair apart diverge into completely different motion within
/// seconds (the classic butterfly-effect demonstration).
///
/// Hold one, `step()` it each frame, and draw the arms through `bob1` and
/// `bob2` (positions relative to the pivot, y down, so translate to the pivot
/// and draw):
///
/// ```swift
/// let pendulum = DoublePendulum(angle1: 2.1, angle2: 2.5)
///
/// override func draw() {
///     pendulum.step()
///     withState {
///         translate(width / 2, height / 3)
///         drawLine(.zero, pendulum.bob1)
///         drawLine(pendulum.bob1, pendulum.bob2)
///     }
/// }
/// ```
///
/// The motion is the exact physics (two point masses on massless arms, no
/// friction), integrated with fixed-step fourth-order Runge-Kutta split into
/// substeps small enough that energy holds steady. There is no randomness and
/// the step is fixed, so a run is a pure function of the starting angles: the
/// same start replays the same chaos every time, and a hair-offset start
/// diverges from it. Angles are radians from hanging straight down.
///
/// Implemented from the published equations of motion (the standard
/// Lagrangian point-mass form), not ported.
public final class DoublePendulum {

    /// The first arm's angle (radians from hanging straight down).
    public var angle1: Double
    /// The second arm's angle (radians from hanging straight down).
    public var angle2: Double
    /// The first arm's angular velocity (radians per second).
    public var velocity1: Double
    /// The second arm's angular velocity (radians per second).
    public var velocity2: Double

    /// The first arm's length, in canvas units.
    public var length1: Double
    /// The second arm's length, in canvas units.
    public var length2: Double
    /// The first bob's mass. Only the ratio to `mass2` matters.
    public var mass1: Double
    /// The second bob's mass. Only the ratio to `mass1` matters.
    public var mass2: Double
    /// Gravity, in canvas units per second squared. The default treats 100
    /// canvas units as a meter.
    public var gravity: Double

    /// A pendulum released from rest at the given angles. The defaults (both
    /// arms raised past horizontal) start it well inside the chaotic regime.
    public init(length1: Double = 200, length2: Double = 200,
                mass1: Double = 1, mass2: Double = 1,
                angle1: Double = 2.1, angle2: Double = 2.5,
                velocity1: Double = 0, velocity2: Double = 0,
                gravity: Double = 980) {
        self.length1 = max(length1, 1e-6)
        self.length2 = max(length2, 1e-6)
        self.mass1 = max(mass1, 1e-9)
        self.mass2 = max(mass2, 1e-9)
        self.angle1 = angle1
        self.angle2 = angle2
        self.velocity1 = velocity1
        self.velocity2 = velocity2
        self.gravity = gravity
    }

    /// The first bob's position relative to the pivot, y down (canvas
    /// orientation): hanging straight down is `(0, length1)`.
    public var bob1: Vector2 {
        Vector2(length1 * sin(angle1), length1 * cos(angle1))
    }

    /// The second bob's position relative to the pivot, y down. This is the
    /// point worth tracing.
    public var bob2: Vector2 {
        bob1 + Vector2(length2 * sin(angle2), length2 * cos(angle2))
    }

    /// The total mechanical energy (kinetic plus potential, zero potential at
    /// the pivot). Constant in the exact dynamics, so watching it is how you
    /// check the integration: it holds to a hair at the default step.
    public var energy: Double {
        let kinetic = 0.5 * mass1 * length1 * length1 * velocity1 * velocity1
            + 0.5 * mass2 * (length1 * length1 * velocity1 * velocity1
                + length2 * length2 * velocity2 * velocity2
                + 2 * length1 * length2 * velocity1 * velocity2 * cos(angle1 - angle2))
        let potential = -(mass1 + mass2) * gravity * length1 * cos(angle1)
            - mass2 * gravity * length2 * cos(angle2)
        return kinetic + potential
    }

    /// Advance the pendulum by `dt` seconds (one frame at 60 fps by default).
    /// The interval is split into fixed Runge-Kutta substeps small enough to
    /// hold energy steady, so a bigger `dt` costs more substeps rather than
    /// accuracy. Calling with the default every frame is deterministic;
    /// passing a live `deltaTime` follows the wall clock instead, at the cost
    /// of exact reproducibility.
    public func advance(by dt: Double = 1.0 / 60.0) {
        guard dt > 0 else { return }
        let substeps = max(1, Int((dt * 480).rounded(.up)))
        let h = dt / Double(substeps)
        var state = State(angle1: angle1, velocity1: velocity1, angle2: angle2, velocity2: velocity2)
        for _ in 0 ..< substeps {
            state = rungeKutta4(state, step: h) { derivative(of: $0) }
        }
        angle1 = state.angle1
        velocity1 = state.velocity1
        angle2 = state.angle2
        velocity2 = state.velocity2
    }

    // MARK: - The equations of motion

    private struct State: Integrable {
        var angle1, velocity1, angle2, velocity2: Double

        static func + (lhs: State, rhs: State) -> State {
            State(angle1: lhs.angle1 + rhs.angle1,
                  velocity1: lhs.velocity1 + rhs.velocity1,
                  angle2: lhs.angle2 + rhs.angle2,
                  velocity2: lhs.velocity2 + rhs.velocity2)
        }

        static func * (scale: Double, value: State) -> State {
            State(angle1: scale * value.angle1,
                  velocity1: scale * value.velocity1,
                  angle2: scale * value.angle2,
                  velocity2: scale * value.velocity2)
        }
    }

    /// The angular accelerations of the two arms in the standard
    /// Lagrangian point-mass form: both share the denominator factor
    /// `2 m1 + m2 - m2 cos(2 a1 - 2 a2)`.
    private func derivative(of s: State) -> State {
        let g = gravity
        let m1 = mass1, m2 = mass2, l1 = length1, l2 = length2
        let a1 = s.angle1, a2 = s.angle2, w1 = s.velocity1, w2 = s.velocity2
        let delta = a1 - a2
        let denominator = 2 * m1 + m2 - m2 * cos(2 * a1 - 2 * a2)

        let acceleration1 = (-g * (2 * m1 + m2) * sin(a1)
            - m2 * g * sin(a1 - 2 * a2)
            - 2 * sin(delta) * m2 * (w2 * w2 * l2 + w1 * w1 * l1 * cos(delta)))
            / (l1 * denominator)
        let acceleration2 = (2 * sin(delta) * (w1 * w1 * l1 * (m1 + m2)
            + g * (m1 + m2) * cos(a1)
            + w2 * w2 * l2 * m2 * cos(delta)))
            / (l2 * denominator)

        return State(angle1: w1, velocity1: acceleration1,
                     angle2: w2, velocity2: acceleration2)
    }
}
