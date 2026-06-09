import Foundation
import Ollin

/// A link that wants to hold two particles a fixed distance apart — a cloth
/// thread, a chain segment, the strut of a soft body.
///
/// It's solved as a **positional constraint** rather than a force: each step the
/// `World` nudges the two particles back toward `length`, splitting the
/// correction by mass (a pinned end doesn't move, a heavy end moves less). With
/// `stiffness` at `1` the link behaves like a rigid stick; lower it and the link
/// gives, springing back over several steps. Because the correction edits
/// positions, the bounce comes through the particles' implicit Verlet velocity
/// for free.
///
/// Create one with `World.connect(_:_:)`, which defaults `length` to the
/// particles' current spacing:
///
/// ```swift
/// let s = world.connect(a, b)        // holds their current distance
/// s.stiffness = 0.4                  // springy instead of rigid
/// ```
public final class Spring {

    /// One end of the link.
    public let a: Particle
    /// The other end.
    public let b: Particle

    /// The distance the link tries to keep between `a` and `b`, in sketch points.
    public var length: Double

    /// How firmly the link pulls back to `length`, `0…1`. `1` is a rigid stick;
    /// smaller values give, so the link reads as a softer spring. Values above
    /// `1` over-correct and can go unstable.
    public var stiffness: Double

    /// Create a link between `a` and `b`.
    /// - Parameters:
    ///   - length: the rest distance; defaults to the current distance between
    ///     the two particles, so connecting two placed particles keeps their
    ///     spacing.
    ///   - stiffness: `0…1`, how hard it pulls back (default rigid).
    public init(_ a: Particle, _ b: Particle, length: Double? = nil, stiffness: Double = 1) {
        self.a = a
        self.b = b
        self.length = length ?? a.position.distance(to: b.position)
        self.stiffness = stiffness
    }

    /// How far the link is from its rest length right now, as a signed fraction
    /// (`0` at rest, positive stretched, negative compressed). Handy for tinting
    /// a cloth by strain.
    public var strain: Double {
        guard length > 0 else { return 0 }
        return (a.position.distance(to: b.position) - length) / length
    }

    /// Pull the two ends back toward `length`. Called by `World.step(dt:)` once
    /// per relaxation iteration; a sketch doesn't call this directly.
    func solve() {
        let delta = b.position - a.position
        let distance = delta.length
        guard distance > 0 else { return }

        let wA = a.pinned ? 0 : a.inverseMass
        let wB = b.pinned ? 0 : b.inverseMass
        let wSum = wA + wB
        guard wSum > 0 else { return }

        // Move each end a mass-weighted share of the way back to rest.
        let difference = (distance - length) / distance
        let correction = delta * (difference * stiffness)
        a.position += correction * (wA / wSum)
        b.position -= correction * (wB / wSum)
    }
}
