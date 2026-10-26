import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// What a 2D soft body touches, and how: friction at every contact, rigid
/// bodies it pushes and is pushed by, and its own far side. No GPU and no
/// timing, so these run anywhere including CI.
@Suite
struct SoftContactTests {

    let canvas = Rectangle(x: 0, y: 0, width: 1080, height: 1080)

    func disc(_ center: Vector2, _ radius: Double, segments: Int = 96) -> Shape {
        Shape(contours: [Circle(center: center, radius: radius).contour(segments: segments)])
    }

    /// A point of a rigid body's frame in the world, the solver's own turn.
    func placed(_ local: Vector2, on center: Vector2, angle: Double) -> Vector2 {
        center + Vector2(local.x * cos(angle) - local.y * sin(angle),
                         local.x * sin(angle) + local.y * cos(angle))
    }

    /// A square of side `side` centered on `center` and turned by `angle`.
    func square(_ center: Vector2, side: Double, angle: Double = 0) -> Shape {
        let h = side / 2
        return Shape([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
            .map { placed($0, on: center, angle: angle) })
    }

    /// A world with a plank tilted by `angle` and a square jelly resting flat
    /// on it, both with `friction`, so the pair rubs with that number (two
    /// surfaces meet with the geometric mean of theirs). A square, since a
    /// round body on a rough slope rolls whatever its friction.
    func slope(angle: Double, friction: Double, plank plankFriction: Double? = nil) throws
        -> (world: World, jelly: SoftBody) {
        let world = World()
        world.bounds = canvas
        let plank = world.addBody(.box(width: 1000, height: 40), at: Vector2(540, 700), kind: .static,
                                  friction: plankFriction ?? friction)
        plank.angle = angle
        // On the plank's upper face, a quarter of the way from its high end.
        let seat = placed(Vector2(-250, -20 - 50), on: plank.position, angle: angle)
        let jelly = try world.addSoftBody(from: square(seat, side: 100, angle: angle), friction: friction)
        return (world, jelly)
    }

    /// How many pairs of the ring's non-neighboring edges cross.
    func crossings(_ body: SoftBody, ring r: Int) -> Int {
        let ring = body.rings[r]
        let n = ring.count
        var count = 0
        for i in ring {
            for j in ring where j > i {
                guard SoftBody.apart(i, j, in: n) > 1 else { continue }
                let a = body.particles[i].position, b = body.particles[body.next[i]].position
                let c = body.particles[j].position, d = body.particles[body.next[j]].position
                let r1 = b - a, r2 = d - c
                let denominator = r1.cross(r2)
                guard abs(denominator) > 1e-12 else { continue }
                let t = (c - a).cross(r2) / denominator
                let u = (c - a).cross(r1) / denominator
                if t > 0, t < 1, u > 0, u < 1 { count += 1 }
            }
        }
        return count
    }

    // MARK: Friction

    @Test func aJellyOnASlopeHoldsAtFullFrictionAndSlidesAtNone() throws {
        // A plank at 0.4 radians has a tangent of 0.42: over the default
        // friction, under 1. A jelly that holds is read after two seconds of
        // settling, over the two that follow; one that slides is read over
        // the second after half a second, while it is still on the plank.
        func drift(friction: Double, plank: Double? = nil, from start: Int, over steps: Int) throws -> Double {
            let (world, jelly) = try slope(angle: 0.4, friction: friction, plank: plank)
            for _ in 0 ..< start { world.advance(by: 1.0 / 60) }
            let settled = jelly.center
            for _ in 0 ..< steps { world.advance(by: 1.0 / 60) }
            return jelly.center.distance(to: settled) / (Double(steps) / 60)
        }
        let grippy = try drift(friction: 1, from: 120, over: 120)
        let plain = try drift(friction: 0.3, from: 30, over: 60)
        let slick = try drift(friction: 0, from: 30, over: 60)
        // Points a second: the grippy one holds (under a tenth of a point a
        // second), the default slides (its friction is under the slope's
        // tangent), and the slick one slides faster: a block's slide down a
        // rough slope is slower by the friction times the slope's cosine, so
        // at 0.3 it gathers about a third of the speed it does at 0.
        #expect(grippy < 0.1)
        #expect(plain > 50 && plain < 200)
        #expect(slick > plain * 2)
        // Two surfaces meet with the geometric mean of their frictions, the
        // rigid side's rule: the default jelly on a plank of friction 1 rubs
        // at 0.55, over the tangent, and holds.
        let mixed = try drift(friction: 0.3, plank: 1, from: 120, over: 120)
        #expect(mixed < 0.1)
    }

    @Test func aJellyOnAJellyRubs() throws {
        func parted(friction: Double) throws -> Double {
            let world = World()
            world.bounds = canvas
            world.drag = 0
            let lower = try world.addSoftBody(from: square(Vector2(300, 1000), side: 160), mass: 3,
                                              friction: friction)
            let upper = try world.addSoftBody(from: square(Vector2(300, 860), side: 100), friction: friction)
            for _ in 0 ..< 60 { world.advance(by: 1.0 / 60) }   // settle the stack
            let gap = upper.center.x - lower.center.x
            upper.push(Vector2(4, 0))
            for _ in 0 ..< 120 { world.advance(by: 1.0 / 60) }
            return abs(upper.center.x - lower.center.x - gap)
        }
        // Pushed sideways, the top jelly slides off a slick one and rides a
        // grippy one, which it drags along with it.
        let slick = try parted(friction: 0)
        let grippy = try parted(friction: 1)
        #expect(slick > 120)
        #expect(grippy < slick / 4)
    }

    @Test func theWallsRubWithTheBodysOwnFriction() throws {
        func slide(friction: Double) throws -> Double {
            let world = World()
            world.bounds = canvas
            world.drag = 0
            let jelly = try world.addSoftBody(from: square(Vector2(200, 1020), side: 120), friction: friction)
            for _ in 0 ..< 30 { world.advance(by: 1.0 / 60) }   // settle on the floor
            let start = jelly.center.x
            jelly.push(Vector2(6, 0))
            for _ in 0 ..< 120 { world.advance(by: 1.0 / 60) }
            return jelly.center.x - start
        }
        let slick = try slide(friction: 0)
        let grippy = try slide(friction: 1)
        // With nothing to slow it the push carries the jelly most of the way
        // across; with full friction the floor takes the push within about
        // the distance a block stops in, its speed squared over twice the
        // friction times gravity, 66 points here.
        #expect(slick > 500)
        #expect(grippy > 30 && grippy < 110)
    }

    @Test func aMovingFloorCarriesWhatRestsOnIt() throws {
        let world = World()
        let belt = world.addBody(.box(width: 2000, height: 40), at: Vector2(540, 800), kind: .kinematic,
                                 friction: 1)
        belt.velocity = Vector2(100, 0)
        let jelly = try world.addSoftBody(from: square(Vector2(300, 720), side: 120), friction: 1)
        for _ in 0 ..< 60 { world.advance(by: 1.0 / 60) }   // land and grip
        let start = jelly.center.x
        for _ in 0 ..< 120 { world.advance(by: 1.0 / 60) }
        // Two seconds at a hundred points a second.
        #expect(abs((jelly.center.x - start) - 200) < 20)
    }

    // MARK: Rigid bodies

    @Test(arguments: [(blob: 2.0, ball: 2.0), (blob: 20.0, ball: 0.2)])
    func momentumCrossesASoftRigidImpactWhole(masses: (blob: Double, ball: Double)) throws {
        // A light blob into a heavy ball, where the particles take nearly the
        // whole correction, and a heavy blob into a light ball, where the
        // ball takes most of it as a pending move the next pass must see.
        let world = World()
        world.gravity = .zero
        world.drag = 0
        let blob = try world.addSoftBody(from: disc(Vector2(300, 540), 80), mass: masses.blob)
        let ball = world.addBody(.circle(radius: 60), at: Vector2(600, 540), density: masses.ball,
                                 restitution: 0.2)
        let h = 1.0 / 60
        blob.push(Vector2(360 * h, 0))
        func momentum() -> Vector2 {
            blob.velocity / h * blob.mass + ball.velocity * ball.mass
        }
        let before = momentum()
        for _ in 0 ..< 120 { world.advance(by: h) }
        let after = momentum()
        // They met, the ball is moving and the blob slower (a heavy blob
        // sweeping a light ball along gives up about a percent), and the
        // total crossed the contact whole.
        #expect(ball.velocity.x > 50)
        #expect(blob.velocity.x / h < 358)
        #expect(abs(after.x - before.x) < before.x * 0.02)
        #expect(abs(after.y) < before.x * 0.02)
    }

    @Test func aBallLandsOnAJellyAndRestsThere() throws {
        let world = World()
        world.bounds = canvas
        // A slab of jelly on the floor, flat on top so the ball has somewhere
        // to rest (on a round jelly it would roll off).
        let slab = Shape([Vector2(340, 920), Vector2(740, 920), Vector2(740, 1080), Vector2(340, 1080)])
        let jelly = try world.addSoftBody(from: slab, mass: 4)
        let ball = world.addBody(.circle(radius: 40), at: Vector2(540, 600), density: 4, restitution: 0)
        var lowest = 0.0
        for _ in 0 ..< 300 {
            world.advance(by: 1.0 / 60)
            lowest = max(lowest, ball.position.y)
        }
        // The ball never got near the floor through the jelly, and it has
        // come to rest in the dent it made, still jiggling a little as a
        // jelly does.
        #expect(lowest < 1080 - 40 - 60)
        #expect(abs(ball.velocity.y) < 15)
        #expect(abs(ball.position.x - 540) < 10)
        // The dent: the slab's top right under the ball is pressed down, and
        // the ball's underside sits on it. The area is kept.
        let dent = jelly.particles.filter { abs($0.position.x - 540) < 15 && $0.position.y < 1000 }
            .map(\.position.y).max()!
        #expect(dent > 925)
        #expect(abs(ball.position.y + 40 - dent) < 3)
        #expect(abs(jelly.area / jelly.restArea - 1) < 0.02)
    }

    @Test func aCrateCornerCannotSinkBetweenTwoParticles() throws {
        // A crate landing corner first on a wide soft slab: the corner meets
        // the outline between its particles, where only the corner test holds
        // it, so it stays within a pixel of the surface throughout.
        let world = World()
        world.bounds = canvas
        let slab = Shape([Vector2(140, 900), Vector2(940, 900), Vector2(940, 1080), Vector2(140, 1080)])
        let soft = try world.addSoftBody(from: slab, mass: 20, spacing: 20, shapeMemory: 0.9)
        let crate = world.addBody(.box(width: 80, height: 80), at: Vector2(548, 700), restitution: 0)
        crate.angle = .pi / 4
        var deepest = 0.0
        for _ in 0 ..< 240 {
            world.advance(by: 1.0 / 60)
            for k in 0 ..< 4 {
                let corner = placed(Vector2(k < 2 ? -40 : 40, k % 2 == 0 ? -40 : 40),
                                    on: crate.position, angle: crate.angle)
                if soft.contains(corner) {
                    deepest = max(deepest, soft.nearestEdge(to: corner, on: [0]).distance)
                }
            }
        }
        #expect(deepest < 1.5)
        #expect(crate.position.y < 900 - 20)
    }

    // MARK: Its own far side

    /// A hairpin: a rope bent into a U, its legs `gap` apart center to center.
    func hairpin(gap: Double, width: Double = 14) -> Shape {
        let top = 200.0, bottom = 700.0, left = 540 - gap / 2, right = 540 + gap / 2
        let w = width / 2
        var points: [Vector2] = []
        points.append(Vector2(left - w, top))
        points.append(Vector2(left + w, top))
        points.append(Vector2(left + w, bottom - w))
        points.append(Vector2(right - w, bottom - w))
        points.append(Vector2(right - w, top))
        points.append(Vector2(right + w, top))
        points.append(Vector2(right + w, bottom + w))
        points.append(Vector2(left - w, bottom + w))
        return Shape(points)
    }

    @Test func aFoldedOutlineStaysOutOfItself() throws {
        func squeezed(collides: Bool) throws -> (crossings: Int, gap: Double) {
            let world = World()
            world.gravity = .zero
            world.drag = 0.05
            let rope = try world.addSoftBody(from: hairpin(gap: 80), spacing: 7, stiffness: 0.9, bend: 0.05,
                                             shapeMemory: 0, collidesWithItself: collides)
            // Press the two legs toward each other for three seconds, a push
            // the drag lets settle at about a point a step, under the
            // thickness, so the legs meet rather than jump each other.
            let press = 200 * rope.particles[0].mass
            for _ in 0 ..< 180 {
                for p in rope.particles where p.position.y < 650 {
                    p.applyForce(Vector2(p.position.x < 540 ? press : -press, 0))
                }
                world.advance(by: 1.0 / 60)
            }
            var worst = Int.min
            for _ in 0 ..< 60 {
                world.advance(by: 1.0 / 60)
                worst = max(worst, crossings(rope, ring: 0))
            }
            // The narrowest gap between the legs' facing sides, read as the
            // x-extent of the material at mid height.
            let mid = rope.particles.filter { abs($0.position.y - 400) < 40 }.map(\.position.x).sorted()
            let gap = mid.count >= 4 ? mid[mid.count / 2] - mid[mid.count / 2 - 1] : 0
            return (worst, gap)
        }
        let through = try squeezed(collides: false)
        let held = try squeezed(collides: true)
        // Without the pass the legs pass through each other and the outline
        // crosses itself; with it the legs stop a thickness short and the
        // outline never crosses.
        #expect(through.crossings > 0)
        #expect(held.crossings == 0)
        #expect(held.gap > 3)
    }

    @Test(arguments: [nil, 12.0])
    func anOutlineThatCannotFoldIsLeftAlone(thickness: Double?) throws {
        func run(collides: Bool) throws -> [Vector2] {
            let world = World()
            world.bounds = canvas
            let body = try world.addSoftBody(from: disc(Vector2(540, 300), 120),
                                             collidesWithItself: collides, thickness: thickness)
            for _ in 0 ..< 180 { world.advance(by: 1.0 / 60) }
            return body.particles.map(\.position)
        }
        // A disc's own edges are never within its thickness of a particle
        // but its neighbors', which the pass skips (more of them when the
        // thickness is wider than the spacing), so the pass changes nothing
        // about a body that cannot fold.
        #expect(try run(collides: true) == run(collides: false))
    }

    // MARK: Settings and repeats

    @Test func theNewSettingsReadAndHold() throws {
        let world = World()
        let body = try world.addSoftBody(from: disc(Vector2(540, 540), 100), spacing: 12)
        #expect(body.friction == 0.3)
        #expect(body.collidesWithItself == false)
        #expect(body.thickness == 6)
        let given = try world.addSoftBody(from: disc(Vector2(200, 200), 50), friction: 0.7,
                                          collidesWithItself: true, thickness: 2.5)
        #expect(given.friction == 0.7 && given.collidesWithItself && given.thickness == 2.5)
        body.friction = .nan
        body.thickness = .infinity
        #expect(body.friction == 0.3 && body.thickness == 6)
        body.friction = -1
        body.thickness = -4
        #expect(body.friction == 0 && body.thickness == 0)
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: disc(.zero, 50), friction: .nan)
        }
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: disc(.zero, 50), thickness: .nan)
        }
    }

    @Test func aRunWithEveryContactRepeatsExactly() throws {
        func run() throws -> [Vector2] {
            let world = World()
            world.bounds = canvas
            let plank = world.addBody(.box(width: 600, height: 30), at: Vector2(400, 700), kind: .static)
            plank.angle = 0.3
            let ball = world.addBody(.circle(radius: 50), at: Vector2(700, 200))
            let bodies = [try world.addSoftBody(from: disc(Vector2(300, 400), 90)),
                          try world.addSoftBody(from: hairpin(gap: 60), spacing: 7, shapeMemory: 0,
                                                collidesWithItself: true)]
            for _ in 0 ..< 240 { world.advance(by: 1.0 / 60) }
            return bodies.flatMap { $0.particles.map(\.position) } + [ball.position]
        }
        #expect(try run() == run())
    }
}
