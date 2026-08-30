import Foundation
import simd
import Ollin
internal import CJolt

/// One segment of a rope: two particles and the rigid rod between them, with
/// the orientation the rod carries.
///
/// The orientation is the point of the thing. A chain of springs knows where
/// its particles are and nothing else, so geometry hung along it can only be
/// guessed at from the neighbors. A rod is a Cosserat rod: it holds a frame of
/// its own, which turns with the rope and twists along it, so a link, a leaf, or
/// a bead placed by `rotation` sits on the rope the way it would in the world.
public struct RopeSegment: Sendable {

    /// Where the segment sits in the rope, counting from the first point.
    public let index: Int

    /// The world position of the particle the segment runs from.
    public let start: Vector3

    /// The world position of the particle it runs to.
    public let end: Vector3

    /// How the segment is turned, with **local +y running along it**, which is
    /// the axis Ollin's cylinders, capsules, and cones stand on, so a primitive
    /// drawn inside `withSegment(_:)` lies along the rope without any turning
    /// of its own. Local +x carries the rope's twist.
    public let rotation: simd_quatd

    /// The middle of the segment, which is where `withSegment(_:)` stands.
    public var center: Vector3 { (start + end) * 0.5 }

    /// Which way the segment points, from `start` to `end`.
    public var direction: Vector3 {
        let span = end - start
        return span.lengthSquared > 1e-18 ? span.normalized : Vector3(0, 1, 0)
    }

    /// How long the segment is right now, which is a little more than its rest
    /// length wherever the rope is under load.
    public var length: Double { (end - start).length }
}

/// A rope: a line of particles held by rigid rods rather than a surface held by
/// springs. Cable, chain, hair, a vine, the stem of a plant, anything whose
/// shape is a curve rather than a skin.
///
/// It is a soft body like any other (it collides with the rigid world, falls
/// into water, reports contacts, and is pinned and dragged by particle), built
/// from the polyline it should rest on. Ollin generates polylines a dozen ways,
/// so a rope can follow anything from three hand-placed points to a `Contour`:
///
/// ```swift
/// let rope = world.addRope(through: (0...24).map { Vector3(0, 3 - Double($0) * 0.1, 0) },
///                          thickness: 0.04,
///                          pinned: { $0.y > 2.9 })       // hung from the top
/// // each frame:
/// world.advance(by: deltaTime)
/// drawSoftBody(rope)
/// ```
///
/// What sets a rope apart from a sheet is that every segment carries its own
/// orientation, so geometry can ride it:
///
/// ```swift
/// for segment in rope.segments {
///     withSegment(segment) { drawTorus(radius: 0.08, tube: 0.02) }
/// }
/// ```
///
/// A rope does not collide with itself, so a coil passes through its own turns.
public final class Rope3D: SoftBody3D {

    /// The polyline the rope was built on, in its own local space. Its points
    /// are the particles one for one, so `pin(_:)`, `move(_:to:)`, and
    /// `positions` all speak in indices into this.
    public let points: [Vector3]

    /// How thick the rope draws and collides, as a radius in world units.
    public var thickness: Double {
        didSet {
            vertexRadius = thickness
            cachedTube = nil
        }
    }

    /// How many sides the drawn tube has around its cross-section.
    public var sides: Int {
        didSet { cachedTube = nil }
    }

    /// The last built tube, and the world step it was built at, so drawing the
    /// same rope twice in a frame sweeps it once.
    private var cachedTube: Mesh?
    private var cachedTubeGeneration = -1

    init?(world: World3D, points: [Vector3], position: Vector3,
          rotation: simd_quatd, thickness: Double, sides: Int, mass: Double,
          stiffness: Double, bend: Double, damping: Double, friction: Double,
          restitution: Double, iterations: Int,
          pinned: ((Vector3) -> Bool)?, maxStretch: Double?,
          group: CollisionGroup, rodRotations: [simd_quatd] = []) {
        // Points that land on top of each other would give a rod no length and
        // no direction to carry, so they are merged rather than refused: a
        // resampled contour or a hand-typed list routinely repeats one.
        var spine: [Vector3] = []
        for point in points where spine.last.map({ ($0 - point).length > 1e-9 }) ?? true {
            spine.append(point)
        }
        self.points = spine
        self.thickness = max(0, thickness)
        self.sides = max(3, sides)
        super.init(world: world, mesh: Mesh(positions: [], indices: []),
                   position: position, rotation: rotation, mass: mass,
                   stiffness: stiffness, bend: bend, pressure: 0,
                   damping: damping, friction: friction,
                   restitution: restitution, iterations: iterations,
                   vertexRadius: max(0, thickness), isTwoSided: true,
                   pinned: pinned, group: group, maxStretch: maxStretch,
                   rope: RopeShape(points: spine, thickness: max(0, thickness),
                                   sides: max(3, sides),
                                   rodRotations: rodRotations))
    }

    /// Every segment of the rope as it stands now, in order from the first
    /// point to the last.
    public var segments: [RopeSegment] {
        let particles = particlePositions
        let orientations = rodOrientations()
        guard particles.count >= 2, orientations.count == rodCount else { return [] }
        return (0 ..< rodCount).map { index in
            RopeSegment(index: index, start: particles[index], end: particles[index + 1],
                        rotation: orientations[index] * Rope3D.alongY)
        }
    }

    /// How many rods run down the rope, which is one fewer than its points.
    public var segmentCount: Int { rodCount }

    /// How long the rope is right now, following its own bends: a little more
    /// than `restLength` wherever it is carrying weight.
    public var length: Double {
        let particles = particlePositions
        guard particles.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1 ..< particles.count { total += (particles[i] - particles[i - 1]).length }
        return total
    }

    /// How long the rope was built to be.
    public var restLength: Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1 ..< points.count { total += (points[i] - points[i - 1]).length }
        return total
    }

    /// The rope as a drawn surface: a tube of `thickness` swept along the
    /// particles, so `drawSoftBody(_:)` works on a rope the way it does on a
    /// sheet. The tube's own cross-section is carried by a twist-free frame
    /// rather than by the rods, so a rope that has been wound up looks the same
    /// as one that has not; the twist is in `segments`, which is where anything
    /// riding the rope should read it.
    public override var mesh: Mesh {
        if let cachedTube, cachedTubeGeneration == world.stepGeneration {
            return cachedTube
        }
        let tube = Mesh.tube(along: particlePositions, radius: thickness, sides: sides)
        cachedTube = tube
        cachedTubeGeneration = world.stepGeneration
        return tube
    }

    /// A quarter turn about x, which takes local +y onto the rod's own +z. Rods
    /// carry a frame whose z runs along them; Ollin's cylinders and capsules
    /// stand on y, so this is what makes a drawn primitive lie along the rope.
    private static let alongY = simd_quatd(angle: .pi / 2,
                                           axis: simd_double3(1, 0, 0))
}
