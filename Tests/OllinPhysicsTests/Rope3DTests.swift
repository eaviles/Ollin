import Foundation
import simd
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for ropes: a polyline becomes a line of particles held by rigid
/// rods, each rod carrying an orientation geometry can ride. Behavioral (the
/// no-pixel-snapshot policy for physics), each one pinned against a
/// counterfactual twin: the same scene run twice with one setting changed.
struct Rope3DTests {

    /// A rope hanging straight down from its first point.
    static func hanging(_ n: Int, spacing: Double = 0.1) -> [Vector3] {
        (0 ..< n).map { Vector3(0, -Double($0) * spacing, 0) }
    }

    /// A rope stuck out sideways from its first point: the cantilever every
    /// bend test measures.
    static func sideways(_ n: Int, spacing: Double = 0.1) -> [Vector3] {
        (0 ..< n).map { Vector3(Double($0) * spacing, 0, 0) }
    }

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// How far the free end of a cantilevered rope has dropped, as a fraction
    /// of the rope's own length: 0 is held out straight, 1 is hanging down.
    func droop(_ rope: Rope3D, from height: Double) -> Double {
        let tip = rope.particlePositions.last ?? .zero
        return (height - tip.y) / max(rope.restLength, 1e-9)
    }

    // MARK: It is a rope

    @Test func aRopeIsBuiltFromItsPolyline() {
        let world = World3D()
        let rope = world.addRope(through: Rope3DTests.hanging(20), at: Vector3(0, 3, 0))
        #expect(rope != nil)
        #expect(rope?.particleCount == 20)
        #expect(rope?.segmentCount == 19)
        #expect(abs((rope?.restLength ?? 0) - 1.9) < 1e-9)
        // A rope has no surface, so the whole pressure story is inert on it.
        #expect(rope?.isClosed == false)
        #expect(rope?.volume == 0)
    }

    @Test func coincidentPointsAreMerged() {
        let world = World3D()
        var points = Rope3DTests.sideways(10)
        points.insert(points[3], at: 4)
        points.insert(points[0], at: 1)
        let rope = world.addRope(through: points, at: Vector3(0, 2, 0))
        // A rod of no length has no direction to carry, so a repeated point is
        // dropped rather than refused.
        #expect(rope?.particleCount == 10)
        #expect(rope?.segmentCount == 9)
    }

    @Test func aRopeOfOnePointIsRefused() {
        let world = World3D()
        #expect(world.addRope(through: [Vector3(0, 1, 0)]) == nil)
        #expect(world.softBodies.isEmpty)
    }

    @Test func aPinnedRopeHangsWhereAFreeOneFalls() {
        func lowestPoint(pinned: Bool) -> Double {
            let world = World3D()
            world.ground = nil
            guard let rope = world.addRope(through: Rope3DTests.hanging(20),
                                           at: Vector3(0, 3, 0), thickness: 0.02,
                                           pinned: pinned ? { $0.y > -0.001 } : nil)
            else { return .nan }
            run(world, steps: 300)
            return rope.particlePositions.map { $0.y }.min() ?? .nan
        }
        let held = lowestPoint(pinned: true)
        let free = lowestPoint(pinned: false)
        // Held, it hangs off its top point; free, it has fallen a long way.
        #expect(held > 1.0)
        #expect(free < -5)
    }

    @Test func pinningNamesThePointsTheClosureChose() {
        let world = World3D()
        guard let rope = world.addRope(through: Rope3DTests.sideways(10),
                                       at: Vector3(0, 2, 0),
                                       pinned: { $0.x < 0.25 })
        else { return }
        // Points 0, 1, and 2 sit at x = 0, 0.1, 0.2.
        #expect(rope.isPinned(0))
        #expect(rope.isPinned(2))
        #expect(!rope.isPinned(3))
        #expect(!rope.isPinned(9))
    }

    // MARK: The knobs

    @Test func aStifferRopeStretchesLess() {
        func stretch(_ stiffness: Double) -> Double {
            let world = World3D()
            world.ground = nil
            guard let rope = world.addRope(through: Rope3DTests.hanging(20),
                                           at: Vector3(0, 3, 0), thickness: 0.02,
                                           mass: 1, stiffness: stiffness,
                                           pinned: { $0.y > -0.001 })
            else { return .nan }
            run(world, steps: 600)
            return rope.length / rope.restLength
        }
        let firm = stretch(1)
        let slack = stretch(0.3)
        #expect(firm < 1.05)
        #expect(slack > 1.3)
        #expect(slack > firm)
    }

    @Test func aBendResistantRopeHoldsItselfOutWhereALimpOneHangs() {
        func drooped(_ bend: Double) -> Double {
            let world = World3D()
            world.ground = nil
            guard let rope = world.addRope(through: Rope3DTests.sideways(20),
                                           at: Vector3(0, 50, 0), thickness: 0.01,
                                           mass: 1, bend: bend, damping: 0.6,
                                           pinned: { $0.x < 0.05 })
            else { return .nan }
            run(world, steps: 3000)
            return droop(rope, from: 50)
        }
        let stem = drooped(1)
        let rope = drooped(0.05)
        #expect(stem < 0.1)          // holds itself out
        #expect(rope > 0.7)          // hangs down
    }

    /// The stage-8 property, for the rod family: one number means the same on a
    /// light rope and a heavy one.
    @Test func bendMeansTheSameAtAnyWeight() {
        func drooped(mass: Double) -> Double {
            let world = World3D()
            world.ground = nil
            guard let rope = world.addRope(through: Rope3DTests.sideways(20),
                                           at: Vector3(0, 50, 0), thickness: 0.01,
                                           mass: mass, bend: 0.5, damping: 0.6,
                                           pinned: { $0.x < 0.05 })
            else { return .nan }
            run(world, steps: 3000)
            return droop(rope, from: 50)
        }
        let light = drooped(mass: 0.2)
        let heavy = drooped(mass: 20)
        #expect(abs(light - heavy) < 0.01)
        #expect(light > 0.15 && light < 0.45)
    }

    /// And the same on ropes of very different length, which took its own
    /// normalization: a bend constraint holds a rotation, which carries no
    /// length to compare against, so the scale had to be measured.
    @Test func bendMeansTheSameAtAnyLength() {
        func drooped(span: Double) -> Double {
            let world = World3D()
            world.ground = nil
            let spacing = span / 19
            guard let rope = world.addRope(through: Rope3DTests.sideways(20, spacing: spacing),
                                           at: Vector3(0, 50, 0), thickness: 0.01,
                                           mass: 1, bend: 0.5, damping: 0.6,
                                           pinned: { $0.x < spacing * 0.5 })
            else { return .nan }
            run(world, steps: 3000)
            return droop(rope, from: 50)
        }
        let short = drooped(span: 0.5)
        let long = drooped(span: 6)
        #expect(abs(short - long) < 0.15)
        #expect(short > 0.15 && short < 0.45)
        #expect(long > 0.15 && long < 0.45)
    }

    @Test func maxStretchCapsAHangingRope() {
        func stretch(_ cap: Double?) -> Double {
            let world = World3D()
            world.ground = nil
            guard let rope = world.addRope(through: Rope3DTests.hanging(20),
                                           at: Vector3(0, 3, 0), thickness: 0.02,
                                           mass: 8, stiffness: 0.3,
                                           pinned: { $0.y > -0.001 },
                                           maxStretch: cap)
            else { return .nan }
            run(world, steps: 600)
            return rope.length / rope.restLength
        }
        // The long range attachments read a rope's connectivity off its rods,
        // so they work with no faces at all, exactly as they do on cloth.
        #expect(stretch(nil) > 1.3)
        #expect(abs(stretch(1) - 1) < 0.02)
    }

    @Test func iterationsSteadyALongFineRope() {
        func drooped(_ iterations: Int) -> Double {
            let world = World3D()
            world.ground = nil
            let spacing = 6.0 / 39
            guard let rope = world.addRope(through: Rope3DTests.sideways(40, spacing: spacing),
                                           at: Vector3(0, 50, 0), thickness: 0.01,
                                           mass: 1, bend: 1, damping: 0.6,
                                           iterations: iterations,
                                           pinned: { $0.x < spacing * 0.5 })
            else { return .nan }
            run(world, steps: 3000)
            return droop(rope, from: 50)
        }
        // Stiffness propagates one rod per pass, so a long finely divided rope
        // needs more passes before it is really rigid.
        #expect(drooped(5) > 0.25)
        #expect(drooped(20) < 0.1)
    }

    // MARK: The orientation, which is the point of a rod

    @Test func everySegmentPointsAlongTheRope() {
        let world = World3D()
        world.ground = nil
        guard let rope = world.addRope(through: Rope3DTests.sideways(12),
                                       at: Vector3(0, 3, 0), thickness: 0.02,
                                       bend: 0.2, damping: 0.4,
                                       pinned: { $0.x < 0.05 })
        else { return }
        run(world, steps: 240)      // let it curve
        var worst = 0.0
        for segment in rope.segments {
            // Local +y is the axis Ollin's cylinders stand on, and it is what
            // `withSegment(_:)` puts along the rope.
            let along = segment.rotation.act(simd_double3(0, 1, 0))
            let direction = segment.direction
            worst = max(worst, simd_length(along - simd_double3(direction.x,
                                                                direction.y,
                                                                direction.z)))
        }
        #expect(worst < 0.05)
        // And the rope really did bend, so this is not a straight-line result.
        #expect((rope.particlePositions.last ?? .zero).y < 2.9)
    }

    @Test func aRopeBuiltTurnedCarriesTurnedFrames() {
        let world = World3D()
        world.ground = nil
        guard let flat = world.addRope(through: Rope3DTests.sideways(8), at: Vector3(0, 3, 0),
                                       thickness: 0.02, pinned: { _ in true }),
              let turned = world.addRope(through: Rope3DTests.sideways(8),
                                         at: Vector3(0, 3, 0), rotation: .pi / 2,
                                         axis: Vector3(0, 1, 0), thickness: 0.02,
                                         pinned: { _ in true })
        else { return }
        run(world, steps: 5)
        let flatAxis = flat.segments[0].rotation.act(simd_double3(0, 1, 0))
        let turnedAxis = turned.segments[0].rotation.act(simd_double3(0, 1, 0))
        // Built along +x, and turned a quarter turn about y, so it runs along
        // -z: the frames turn with the body, they are not re-derived flat.
        #expect(abs(flatAxis.x - 1) < 1e-3)
        #expect(abs(turnedAxis.z + 1) < 1e-3)
    }

    // MARK: A member of the world

    @Test func aRopeDrapesOverACrateRatherThanThroughIt() {
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 0.5, 0),
                      kind: .static)
        guard let rope = world.addRope(through: Rope3DTests.sideways(24),
                                       at: Vector3(-1.2, 2, 0),
                                       thickness: 0.05, mass: 1)
        else { return }
        run(world, steps: 300)
        // The middle of the rope lies on the crate's lid, one thickness above
        // it, while its ends have fallen past the sides.
        let overCrate = rope.particlePositions.filter { abs($0.x) < 0.4 }
        #expect(overCrate.allSatisfy { abs($0.y - 1.05) < 0.02 })
        #expect((rope.particlePositions.first ?? .zero).y < 0.5)
        #expect(rope.touching.count >= 1)
    }

    @Test func aRopePushesALightBodyOutOfItsWay() {
        func pebbleTravel(withRope: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            let pebble = world.addBody(.sphere(radius: 0.1), at: Vector3(0, 0.1, 0),
                                       density: 0.1)
            if withRope {
                world.addRope(through: Rope3DTests.sideways(20), at: Vector3(-1, 1.5, 0),
                              thickness: 0.05, mass: 2)
            }
            run(world, steps: 240)
            return (pebble.position - Vector3(0, 0.1, 0)).length
        }
        #expect(pebbleTravel(withRope: true) > 0.1)
        #expect(pebbleTravel(withRope: false) < 0.01)
    }

    @Test func aRopeFloatsAtTheDensityItIsGiven() {
        func settledHeight(density: Double, dry: Bool = false) -> Double {
            let world = World3D()
            world.ground = -6
            if !dry { world.water = Water(level: 0) }
            guard let rope = world.addRope(through: Rope3DTests.sideways(20),
                                           at: Vector3(0, 2, 0), thickness: 0.05,
                                           mass: 0.4)
            else { return .nan }
            rope.density = density
            run(world, steps: 500)
            return rope.center.y
        }
        // A light rope rides the surface. A heavy one sinks, but slowly: a
        // rope's area for its weight is enormous, so the water's drag holds it
        // back, and the counterfactual that shows the water is doing anything
        // is the same rope in a dry world, which is on the floor by then.
        #expect(abs(settledHeight(density: 0.4)) < 0.1)
        #expect(settledHeight(density: 4) < -0.4)
        #expect(settledHeight(density: 4, dry: true) < -5.5)
    }

    /// The envelope, stated rather than faked: the shape a query asks about is
    /// built from a body's faces, and a rope has none.
    @Test func aRopeIsInvisibleToQueries() {
        let world = World3D()
        world.ground = -5
        guard let rope = world.addRope(through: Rope3DTests.sideways(20),
                                       at: Vector3(0, 1, 0), thickness: 0.1,
                                       pinned: { _ in true })
        else { return }
        run(world, steps: 10)
        #expect(world.raycast(from: Vector3(0.9, 3, 0), to: Vector3(0.9, -1, 0)) == nil)
        #expect(world.sweep(.sphere(radius: 0.2), from: Vector3(0.9, 3, 0),
                            to: Vector3(0.9, -1, 0)) == nil)
        #expect(world.bodiesOverlapping(.sphere(radius: 0.3),
                                        at: Vector3(0.9, 1, 0)).isEmpty)
        // What still works is asking the rope itself.
        #expect(rope.nearestVertex(to: Vector3(1, 1, 0)) == 10)
    }

    // MARK: Putting one back

    @Test func aSavedRopeComesBackWhereItWas() {
        let world = World3D()
        world.ground = nil
        guard let rope = world.addRope(through: Rope3DTests.sideways(12),
                                       at: Vector3(0, 2, 0), thickness: 0.03,
                                       bend: 0.3, damping: 0.6,
                                       pinned: { $0.x < 0.05 })
        else { return }
        run(world, steps: 900)
        let saved = rope.particlePositions
        let snapshot = world.snapshot()

        let back = World3D()
        back.ground = nil
        back.restore(snapshot)
        guard let restored = back.softBodies.first as? Rope3D else {
            Issue.record("the rope did not come back")
            return
        }
        // A rope carries its own rest shape, so it needs no resolver at all.
        #expect(snapshot.assetNames.isEmpty)
        #expect(restored.particleCount == 12)
        #expect(restored.isPinned(0))
        #expect(abs(restored.restLength - rope.restLength) < 1e-9)
        var worst = 0.0
        for (a, b) in zip(saved, restored.particlePositions) {
            worst = max(worst, (a - b).length)
        }
        #expect(worst < 1e-6)
    }

    /// The rods' own orientations have to travel with the shape. Without them
    /// every rod opens in the frame the rest polyline gives and the solver
    /// hauls it round to the shape the rope is actually in, which reads as a
    /// spring on the first frame.
    @Test func aRestoredRopeDoesNotSpring() {
        func settle() -> (World3D, Rope3D) {
            let world = World3D()
            world.ground = nil
            let rope = world.addRope(through: Rope3DTests.sideways(12),
                                     at: Vector3(0, 2, 0), thickness: 0.03,
                                     bend: 0.3, damping: 0.6,
                                     pinned: { $0.x < 0.05 })!
            run(world, steps: 900)
            return (world, rope)
        }
        let (world, rope) = settle()
        let saved = rope.particlePositions
        let velocities = rope.particleVelocities
        let frames = rope.rodOrientations()

        func drift(carryingFrames: Bool) -> Double {
            let back = World3D()
            back.ground = nil
            guard let twin = back.makeRope(points: Rope3DTests.sideways(12),
                                           position: Vector3(0, 2, 0),
                                           rotation: simd_quatd(angle: 0,
                                                                axis: simd_double3(0, 1, 0)),
                                           thickness: 0.03, sides: 8, mass: 1,
                                           stiffness: 1, bend: 0.3, damping: 0.6,
                                           friction: 0.5, restitution: 0,
                                           iterations: 5,
                                           pinned: { $0.x < 0.05 }, maxStretch: nil,
                                           group: .default,
                                           rodRotations: carryingFrames ? frames : [])
            else { return .nan }
            twin.restoreState(positions: saved, velocities: velocities)
            run(back, steps: 2)
            var worst = 0.0
            for (a, b) in zip(saved, twin.particlePositions) {
                worst = max(worst, (a - b).length)
            }
            return worst
        }
        let carried = drift(carryingFrames: true)
        let dropped = drift(carryingFrames: false)
        #expect(carried < 0.01)
        #expect(dropped > 0.1)
        #expect(dropped > carried * 20)
        _ = world
    }

    @Test func identicalRopesReplayIdentically() {
        func trace() -> [Vector3] {
            let world = World3D()
            world.ground = 0
            guard let rope = world.addRope(through: Rope3DTests.sideways(16),
                                           at: Vector3(0, 2, 0), thickness: 0.03,
                                           bend: 0.4, pinned: { $0.x < 0.05 })
            else { return [] }
            run(world, steps: 400)
            return rope.particlePositions
        }
        let first = trace()
        let second = trace()
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) { #expect(a == b) }
    }
}
