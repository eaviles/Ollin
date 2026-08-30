import Foundation
import Ollin

/// A point mass in a `World` — the body the simulation moves.
///
/// Motion is **Verlet**: instead of storing a velocity, a particle keeps its
/// `previous` position, and the velocity is the gap between the two. The
/// integrator reads that gap, so to *give* a particle a velocity you nudge
/// `previous` (or call `push(_:)`), and to teleport it without imparting any
/// you call `place(at:)` (which moves `previous` along with it). This is what
/// makes constraints cheap: a `Spring` or a collision just edits `position`,
/// and the velocity follows for free on the next step.
///
/// A `Particle` is a reference type on purpose. Springs and collisions hold
/// onto the same particles and adjust them in place, so they share identity
/// rather than copies — the one place Ollin reaches for reference semantics
/// instead of value types.
///
/// ```swift
/// let p = world.addParticle(at: Vector2(540, 200), radius: 24)
/// p.push(Vector2(120, 0))   // launch it to the right
/// ```
public final class Particle {

    /// Where the particle is now, in sketch points (top-left origin, y-down).
    public var position: Vector2

    /// Where it was on the previous step. The implicit velocity is
    /// `position - previous`; the integrator and constraints maintain it.
    public var previous: Vector2

    /// Force accumulated for the next step, cleared when the `World` integrates.
    /// Prefer `applyForce(_:)` over writing this directly.
    public var acceleration: Vector2 = .zero

    /// Collision radius. `0` makes the particle a pure point (it takes part in
    /// springs and bounds but never collides with other particles); a positive
    /// radius lets it collide as a disk when `World.particlesCollide` is on.
    public var radius: Double

    /// `1 / mass`, the weight constraints use to share a correction. A heavier
    /// particle (smaller inverse mass) moves less when pushed. `0` means
    /// infinite mass — see `pinned`.
    public var inverseMass: Double

    /// When `true`, the particle is held in place: the integrator skips it and
    /// constraints treat it as immovable (infinite mass). Use it for anchors —
    /// the top of a cloth, a fixed pivot.
    public var isPinned: Bool = false

    /// Free-form tag so a sketch can hang its own data off a particle (an index,
    /// a color, a group id) without a parallel array.
    public var userData: Any?

    /// Create a particle at `position`.
    /// - Parameters:
    ///   - position: starting location, in sketch points.
    ///   - radius: collision radius; `0` for a non-colliding point.
    ///   - mass: heavier particles resist being pushed; must be `> 0`.
    public init(position: Vector2, radius: Double = 0, mass: Double = 1) {
        self.position = position
        self.previous = position
        self.radius = radius
        self.inverseMass = mass > 0 ? 1 / mass : 0
    }

    /// The particle's mass. Reading it inverts `inverseMass`; a pinned (infinite
    /// mass) particle reads `.infinity`. Setting `0` or less pins it.
    public var mass: Double {
        get { inverseMass > 0 ? 1 / inverseMass : .infinity }
        set { inverseMass = newValue > 0 ? 1 / newValue : 0 }
    }

    /// The implicit velocity, as a per-step displacement (`position - previous`).
    /// It isn't divided by the timestep — it's "how far it moved last step" —
    /// which is the quantity the Verlet integrator carries forward.
    public var velocity: Vector2 { position - previous }

    /// Accumulate a force for the next step. Mass is taken into account, so the
    /// same force moves a light particle more than a heavy one. Has no effect on
    /// a pinned particle.
    public func applyForce(_ force: Vector2) {
        acceleration += force * inverseMass
    }

    /// Add to the implicit velocity by nudging `previous`. `amount` is a
    /// per-step displacement, the same units as `velocity`.
    public func push(_ amount: Vector2) {
        previous -= amount
    }

    /// Move the particle to `point` without imparting any velocity (both
    /// `position` and `previous` jump together). Use this to teleport — for a
    /// throw, set the position and then `push(_:)`.
    public func place(at point: Vector2) {
        position = point
        previous = point
    }

    /// Pin the particle in place (anchor it). Equivalent to `isPinned = true`.
    @discardableResult
    public func pin() -> Particle { isPinned = true; return self }

    /// Release a pinned particle so forces and constraints move it again.
    @discardableResult
    public func unpin() -> Particle { isPinned = false; return self }
}
