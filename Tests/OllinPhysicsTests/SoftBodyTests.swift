import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// The 2D soft body: an outline that keeps its area, holds its shape by as
/// much as it is told to, and never lets another outline in. No GPU and no
/// timing, so these run anywhere including CI.
@Suite
struct SoftBodyTests {

    let canvas = Rectangle(x: 0, y: 0, width: 1080, height: 1080)

    func disc(_ center: Vector2, _ radius: Double) -> Shape {
        Shape(contours: [Circle(center: center, radius: radius).contour(segments: 128)])
    }

    func star(at center: Vector2) -> Shape {
        Shape(contours: [Contour((0 ..< 10).map { k in
            center + Vector2(angle: Double(k) / 10 * .tau - .pi / 2,
                             length: k.isMultiple(of: 2) ? 150 : 65)
        })])
    }

    /// A ring: a disc with a disc-shaped counter.
    func ring(_ center: Vector2) -> Shape {
        Shape(contours: [Circle(center: center, radius: 150).contour(segments: 128),
                         Circle(center: center, radius: 80).contour(segments: 128)])
    }

    /// How far the particles sit from the rest shape fitted to them by the
    /// best turn and shift, as a root mean square.
    func shapeError(_ body: SoftBody) -> Double {
        let c = body.center
        var cosines = 0.0, sines = 0.0
        for (i, p) in body.particles.enumerated() {
            let d = p.position - c, q = body.restOffsets[i]
            cosines += d.dot(q)
            sines += q.cross(d)
        }
        let turn = atan2(sines, cosines)
        var sum = 0.0
        for (i, p) in body.particles.enumerated() {
            sum += (p.position - c - body.restOffsets[i].rotated(by: turn)).lengthSquared
        }
        return (sum / Double(body.particles.count)).squareRoot()
    }

    /// How deep any particle of `a` sits inside `b`.
    func depth(of a: SoftBody, in b: SoftBody) -> Double {
        var worst = 0.0
        for p in a.particles where b.contains(p.position) {
            worst = max(worst, b.nearestEdge(to: p.position, on: Array(b.rings.indices)).distance)
        }
        return worst
    }

    // MARK: The three promises

    @Test func aBodyKeepsItsAreaThroughADrop() throws {
        let world = World()
        world.bounds = canvas
        let body = try world.addSoftBody(from: disc(Vector2(540, 300), 120))
        let rest = body.area
        #expect(abs(rest - .pi * 120 * 120) < .pi * 120 * 120 * 0.01)
        var worst = 0.0
        for _ in 0 ..< 360 {
            world.advance(by: 1.0 / 60)
            worst = max(worst, abs(body.area / rest - 1))
        }
        // It landed and squashed: the area held while the shape did not.
        #expect(body.center.y > 900)
        #expect(worst < 0.02)
    }

    @Test func noGiveIsRigidAndTheDefaultIsNot() throws {
        /// The worst shape error of a spinning star, and of the same star
        /// dropped onto the floor.
        func worst(memory: Double) throws -> (spinning: Double, landing: Double) {
            let space = World()
            space.gravity = .zero
            space.drag = 0
            let spinning = try space.addSoftBody(from: star(at: Vector2(540, 540)),
                                                 shapeMemory: memory)
            for p in spinning.particles {
                p.push((p.position - spinning.center).perpendicular * 0.05)
            }
            var spin = 0.0
            for _ in 0 ..< 120 {
                space.advance(by: 1.0 / 60)
                spin = max(spin, shapeError(spinning))
            }
            let world = World()
            world.bounds = canvas
            let dropped = try world.addSoftBody(from: star(at: Vector2(540, 300)),
                                                shapeMemory: memory)
            var landing = 0.0
            for _ in 0 ..< 240 {
                world.advance(by: 1.0 / 60)
                landing = max(landing, shapeError(dropped))
            }
            return (spin, landing)
        }
        // A shape memory of 1 is a compliance of zero: a spinning star stays
        // exactly the star. Landing it still gives a little, since the floor is
        // the last thing a pass holds to, but a fraction of what the default
        // gives, which is what keeps the first reading from passing on a
        // solver that moves nothing.
        let rigid = try worst(memory: 1)
        let soft = try worst(memory: 0.3)
        #expect(rigid.spinning < 1e-6)
        #expect(soft.spinning > 0.1)
        #expect(rigid.landing < soft.landing / 3)
    }

    @Test func twoBodiesNeverSinkIntoEachOther() throws {
        let world = World()
        world.bounds = canvas
        let a = try world.addSoftBody(from: disc(Vector2(540, 800), 120))
        let b = try world.addSoftBody(from: disc(Vector2(560, 450), 120))
        let c = try world.addSoftBody(from: star(at: Vector2(500, 150)))
        var worst = 0.0
        for _ in 0 ..< 600 {
            world.advance(by: 1.0 / 60)
            for (x, y) in [(a, b), (b, a), (a, c), (c, a), (b, c), (c, b)] {
                worst = max(worst, depth(of: x, in: y))
            }
        }
        #expect(worst < 1)
        // And they did meet: the three are piled, not side by side.
        #expect(c.center.y < a.center.y || c.center.y < b.center.y)
    }

    // MARK: Settings

    @Test func aSettingMeansTheSameBodyAtAnyFrameRate() throws {
        var heights: [Double] = []
        for rate in [30.0, 60, 120, 240] {
            let world = World()
            world.bounds = canvas
            world.drag = 0.05
            let body = try world.addSoftBody(from: disc(Vector2(540, 900), 120),
                                             stiffness: 0.5, bend: 0.1, pressure: 5, shapeMemory: 0)
            for _ in 0 ..< Int(rate * 6) { world.advance(by: 1 / rate) }
            heights.append(body.shape.bounds!.height)
        }
        // Soft enough to sag by a third, and that sag within 3% whatever
        // the step: compliance divided by the step squared is what keeps it.
        #expect(heights.allSatisfy { $0 < 180 })
        #expect(heights.max()! / heights.min()! < 1.03)
    }

    @Test func pressureSetsHowMuchAreaItsWeightPressesOut() throws {
        func settledArea(_ pressure: Double) throws -> Double {
            let world = World()
            world.bounds = canvas
            world.drag = 0.1
            let body = try world.addSoftBody(from: disc(Vector2(540, 950), 120), stiffness: 0.5,
                                             bend: 0.1, pressure: pressure, shapeMemory: 0)
            for _ in 0 ..< 600 { world.advance(by: 1.0 / 60) }
            return body.area / body.restArea
        }
        let held = try settledArea(.infinity)
        let firm = try settledArea(50)
        let soft = try settledArea(5)
        #expect(abs(held - 1) < 0.005)
        #expect(firm < held && soft < firm)
        #expect(soft > 0.7)
    }

    @Test func restAreaInflatesTheBody() throws {
        let world = World()
        world.gravity = .zero
        let body = try world.addSoftBody(from: disc(Vector2(540, 540), 100), shapeMemory: 0)
        body.restArea *= 1.5
        for _ in 0 ..< 240 { world.advance(by: 1.0 / 60) }
        #expect(abs(body.area / (body.restArea) - 1) < 0.01)
        #expect(abs(body.area / (.pi * 100 * 100) - 1.5) < 0.02)
    }

    @Test func settingsTheSolverCannotHoldAreIgnored() throws {
        let world = World()
        let body = try world.addSoftBody(from: disc(Vector2(540, 540), 100))
        body.stiffness = .nan
        body.bend = .infinity
        body.shapeMemory = .nan
        body.pressure = .nan
        body.restArea = .nan
        #expect(body.stiffness == 0.8 && body.bend == 0.2 && body.shapeMemory == 0.3)
        #expect(body.pressure == .infinity && body.restArea.isFinite)
        body.pressure = 10
        #expect(body.pressure == 10)
    }

    // MARK: Outlines

    @Test func aCounterStaysOpenAndInside() throws {
        let world = World()
        world.bounds = canvas
        // No shape memory, so nothing but the rings themselves holds the
        // counter up: it falls onto the bottom of the outline and rests there.
        // Without the rings kept apart it falls 13 points through.
        let body = try world.addSoftBody(from: ring(Vector2(540, 300)), shapeMemory: 0)
        #expect(body.rings.count == 2 && body.islands == [[0, 1]])
        #expect(abs(body.area / (.pi * (150 * 150 - 80 * 80)) - 1) < 0.01)
        let counter = abs(body.ringArea(1))
        var outside = 0.0
        for _ in 0 ..< 360 {
            world.advance(by: 1.0 / 60)
            for i in body.rings[1] where !body.ring(0, contains: body.particles[i].position) {
                outside = max(outside, body.nearestEdge(to: body.particles[i].position, on: [0]).distance)
            }
        }
        #expect(outside < 1)
        #expect(abs(abs(body.ringArea(1)) / counter - 1) < 0.05)
        // The counter is still a hole: a point at its middle is not the body.
        let middle = body.rings[1].reduce(Vector2.zero) { $0 + body.particles[$1].position }
            / Double(body.rings[1].count)
        #expect(!body.contains(middle))
    }

    @Test func cornersAreKeptAsParticles() throws {
        let world = World()
        let square = Shape(contours: [Contour([Vector2(100, 100), Vector2(300, 100),
                                               Vector2(300, 300), Vector2(100, 300)])])
        let body = try world.addSoftBody(from: square, spacing: 30)
        let positions = body.particles.map(\.position)
        for corner in [Vector2(100, 100), Vector2(300, 100), Vector2(300, 300), Vector2(100, 300)] {
            #expect(positions.contains { $0.distance(to: corner) < 1e-6 })
        }
        // Each side cut evenly, close to the spacing asked for.
        #expect(body.particles.count == 28)
        #expect(body.restLengths.allSatisfy { abs($0 - 200.0 / 7) < 1e-6 })

        let pointed = try world.addSoftBody(from: star(at: Vector2(600, 600)))
        let tips = (0 ..< 10).map { k in
            Vector2(600, 600) + Vector2(angle: Double(k) / 10 * .tau - .pi / 2,
                                        length: k.isMultiple(of: 2) ? 150 : 65)
        }
        for tip in tips {
            #expect(pointed.particles.contains { $0.position.distance(to: tip) < 1e-6 })
        }
    }

    @Test func islandsAndHolesAreFoundWhicheverWayTheyWind() throws {
        let world = World()
        // Two islands, the second with a hole wound the same way as its
        // outline: the even-odd fill still reads it as a hole.
        let square = { (x: Double, y: Double, s: Double) in
            Contour([Vector2(x, y), Vector2(x + s, y), Vector2(x + s, y + s), Vector2(x, y + s)])
        }
        let shape = Shape(contours: [square(100, 100, 100), square(400, 100, 200),
                                     square(450, 150, 100)])
        let body = try world.addSoftBody(from: shape)
        #expect(body.islands.count == 2)
        #expect(body.rings.count == 3)
        #expect(abs(body.area - (100 * 100 + 200 * 200 - 100 * 100)) < 1)
        for island in body.islands {
            #expect(body.ringArea(island[0]) > 0)
            for hole in island.dropFirst() { #expect(body.ringArea(hole) < 0) }
        }
        #expect(!body.contains(Vector2(500, 200)))
        #expect(body.contains(Vector2(420, 120)))
    }

    @Test func shapesItCannotBuildFromThrow() throws {
        let world = World()
        #expect(throws: PhysicsError.self) { try world.addSoftBody(from: Shape(contours: [])) }
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)],
                                              closed: false))
        }
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: Shape([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]))
        }
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: Shape([Vector2(0, 0), Vector2(.nan, 0), Vector2(0, 100)]))
        }
        #expect(throws: PhysicsError.self) { try world.addSoftBody(from: disc(.zero, 50), mass: 0) }
        #expect(throws: PhysicsError.self) { try world.addSoftBody(from: disc(.zero, 50), spacing: 0) }
        #expect(throws: PhysicsError.self) {
            try world.addSoftBody(from: disc(.zero, 50), stiffness: .nan)
        }
        #expect(world.particles.isEmpty && world.softBodies.isEmpty)
    }

    // MARK: The world around it

    @Test func looseDisksStayOutsideABody() throws {
        let world = World()
        world.bounds = canvas
        world.particlesCollide = true
        let body = try world.addSoftBody(from: disc(Vector2(540, 960), 120))
        let balls = (0 ..< 12).map { k in
            world.addParticle(at: Vector2(380 + Double(k % 4) * 100, 300 + Double(k / 4) * 90),
                              radius: 20)
        }
        // A ball may roll off the dome, there being no friction, and one
        // wedged between the floor and the body's side can overlap it for a
        // step as it lands, the floor being the last thing a pass holds to.
        // Its center never gets inside, and once settled every ball sits its
        // own radius clear.
        func gap(_ ball: Particle) -> Double {
            let distance = body.nearestEdge(to: ball.position, on: [0]).distance
            return body.contains(ball.position) ? -distance : distance
        }
        var closest = Double.infinity
        for _ in 0 ..< 360 {
            world.advance(by: 1.0 / 60)
            for ball in balls { closest = min(closest, gap(ball)) }
        }
        #expect(closest > 0)
        #expect(balls.allSatisfy { gap($0) > 19 })
    }

    @Test func pushAndForceMoveTheWholeBody() throws {
        let world = World()
        world.gravity = .zero
        world.drag = 0
        let body = try world.addSoftBody(from: disc(Vector2(540, 540), 100), mass: 2)
        body.push(Vector2(3, 0))
        world.advance(by: 1.0 / 60)
        #expect(abs(body.velocity.x - 3) < 1e-9)

        let other = World()
        other.gravity = .zero
        other.drag = 0
        let still = try other.addSoftBody(from: disc(Vector2(540, 540), 100), mass: 2)
        still.applyForce(Vector2(0, 400))
        other.advance(by: 1.0 / 60)
        // Force over mass, through one step: a·dt² of displacement.
        #expect(abs(still.velocity.y - 200.0 / 3600) < 1e-9)

        let before = body.center
        body.move(by: Vector2(10, -20))
        #expect(body.center.distance(to: before + Vector2(10, -20)) < 1e-9)
        #expect(abs(body.velocity.x - 3) < 1e-9)
    }

    @Test func removingABodyTakesItsParticlesAndOneParticleTakesItsBody() throws {
        let world = World()
        let loose = world.addParticle(at: .zero)
        let a = try world.addSoftBody(from: disc(Vector2(200, 200), 80))
        let b = try world.addSoftBody(from: disc(Vector2(600, 200), 80))
        world.connect(loose, a.particles[0])
        world.remove(a)
        #expect(world.softBodies.count == 1 && world.particles.count == 1 + b.particles.count)
        #expect(world.springs.isEmpty)
        world.remove(b.particles[3])
        #expect(world.softBodies.isEmpty && world.particles.count == 1)
        let c = try world.addSoftBody(from: disc(Vector2(200, 200), 80))
        world.removeAll()
        #expect(world.softBodies.isEmpty && world.particles.isEmpty)
        _ = c
    }

    @Test func aRunRepeatsExactly() throws {
        func run() throws -> [Vector2] {
            let world = World()
            world.bounds = canvas
            let bodies = [try world.addSoftBody(from: disc(Vector2(500, 300), 110)),
                          try world.addSoftBody(from: star(at: Vector2(600, 600))),
                          try world.addSoftBody(from: ring(Vector2(400, 850)))]
            for _ in 0 ..< 240 { world.advance(by: 1.0 / 60) }
            return bodies.flatMap { $0.particles.map(\.position) }
        }
        #expect(try run() == run())
    }
}
