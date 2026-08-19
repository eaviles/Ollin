import Foundation
import Testing
import Ollin
import CJolt
@testable import OllinPhysics

/// Correctness for contact events and sensor bodies: touches arrive as a
/// per-step list a `draw()` poll can read, a pair reports once however many of
/// its shapes are in contact, a sensor reports what passes through without
/// pushing it, and a body that falls asleep inside a sensor keeps being
/// reported. Behavioral (the no-pixel-snapshot policy for physics), each knob
/// pinned against a counterfactual twin where one exists; parallel-safe like
/// the rest of the 3D suite.
struct Contact3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// Step until `body` reports something, up to `limit` steps, and return
    /// every contact seen along the way (each step's list, concatenated).
    @discardableResult
    func collect(_ world: World3D, steps: Int, dt: Double = 1.0 / 60)
        -> [Contact3D] {
        var seen: [Contact3D] = []
        for _ in 0 ..< steps {
            world.step(dt: dt)
            seen.append(contentsOf: world.contacts)
        }
        return seen
    }

    // MARK: Landing on the floor

    @Test func aFallingBodyReportsItsLanding() {
        let world = World3D()
        world.ground = 0
        let ball = world.addBody(.sphere(radius: 0.5), at: Vector3(0, 3, 0),
                                 restitution: 0)

        let seen = collect(world, steps: 90)
        let landings = seen.filter { $0.phase == .began && $0.involves(ball) }
        // Only ever the one partner: a ball on an empty floor.
        let partners = Set(landings.compactMap {
            $0.other(than: ball).map(ObjectIdentifier.init)
        })
        #expect(partners == [ObjectIdentifier(try! #require(world.groundBody))])

        let landing = try! #require(landings.first)
        // The floor slab is a body too, just not one the sketch added.
        #expect(landing.other(than: ball) === world.groundBody)
        #expect(abs(landing.point.y) < 0.05)          // touched at y = 0
        #expect(landing.speed > 4)                    // ≈ √(2·9.8·2.5) = 7 units/s

        // The normal points from a toward b, whichever way round the pair fell.
        let a = try! #require(landing.a as? Body3D)
        let b = try! #require(landing.b as? Body3D)
        let toB = b.position - a.position
        #expect(landing.normal.dot(toB) > 0)
        #expect(abs(abs(landing.normal.y) - 1) < 0.01)
    }

    /// The impact reads the speed at the moment of contact, before the solver
    /// answers it, so a longer drop lands harder in the ratio free fall says.
    @Test func impactSpeedFollowsTheDrop() {
        func landingSpeed(from height: Double) -> Double {
            let world = World3D()
            world.ground = 0
            let ball = world.addBody(.sphere(radius: 0.5), at: Vector3(0, height, 0))
            let seen = collect(world, steps: 180)
            return seen.first { $0.phase == .began && $0.involves(ball) }?.speed ?? 0
        }

        let shallow = landingSpeed(from: 1.5)     // 1 unit of fall
        let deep = landingSpeed(from: 8.5)        // 8 units of fall
        #expect(shallow > 3 && shallow < 6)       // √(2·9.8·1) ≈ 4.4
        #expect(deep > 11 && deep < 14)           // √(2·9.8·8) ≈ 12.5
        #expect(deep > shallow * 2)
    }

    // MARK: One event per pair

    /// A body whose collider is several shapes touches the floor in several
    /// places at once, and a mesh floor would be touched along many triangles.
    /// The pair still reports once: no step ever carries the same pair twice.
    /// The counterfactual twin is the same two boxes as separate bodies, which
    /// is genuinely two pairs and does report two events in the landing step.
    @Test func aPairReportsOnceHoweverManyShapesTouch() {
        func pairKey(_ contact: Contact3D) -> String {
            "\(ObjectIdentifier(contact.a))-\(ObjectIdentifier(contact.b))"
        }
        /// Every step's began events, for a run.
        func beginnings(_ world: World3D, steps: Int) -> [[Contact3D]] {
            (0 ..< steps).map { _ in
                world.step(dt: 1.0 / 60)
                return world.contacts.filter { $0.phase == .began }
            }
        }

        let fused = World3D()
        fused.ground = 0
        // Two feet a body-width apart: both land in the same step.
        fused.addBody(.compound([
            .part(.box(width: 1, height: 0.4, depth: 1), at: Vector3(-1.2, 0, 0)),
            .part(.box(width: 1, height: 0.4, depth: 1), at: Vector3(1.2, 0, 0)),
        ]), at: Vector3(0, 1.2, 0), restitution: 0)
        let fusedSteps = beginnings(fused, steps: 120)
        for step in fusedSteps {
            #expect(step.count == Set(step.map(pairKey)).count)
        }
        #expect(fusedSteps.first { !$0.isEmpty }?.count == 1)

        let loose = World3D()
        loose.ground = 0
        let left = loose.addBody(.box(width: 1, height: 0.4, depth: 1),
                                 at: Vector3(-1.2, 1.2, 0), restitution: 0)
        let right = loose.addBody(.box(width: 1, height: 0.4, depth: 1),
                                  at: Vector3(1.2, 1.2, 0), restitution: 0)
        let looseSteps = beginnings(loose, steps: 120)
        let landing = try! #require(looseSteps.first { !$0.isEmpty })
        #expect(landing.count == 2)
        #expect(landing.contains { $0.involves(left) })
        #expect(landing.contains { $0.involves(right) })
    }

    // MARK: Draining

    /// Contacts are transitions, not state: the step that filled the list owns
    /// it, reading it twice is not draining it, and a scene lying still
    /// reports nothing at all while `touching` still says what rests on what.
    @Test func contactsBelongToTheirStep() {
        let world = World3D()
        world.ground = 0
        let ball = world.addBody(.sphere(radius: 0.5), at: Vector3(0, 1.2, 0),
                                 restitution: 0)
        let floor = try! #require(world.groundBody)

        var landed = false
        for _ in 0 ..< 120 where !landed {
            world.step(dt: 1.0 / 60)
            landed = world.contacts.contains { $0.phase == .began }
        }
        #expect(landed)

        // Reading is not draining: every part of a frame that asks gets the
        // same list.
        let first = world.contacts
        let second = world.contacts
        #expect(first.count == second.count)
        #expect(first.count == 1)
        #expect(second.first?.involves(ball) == true)
        #expect(ball.isTouching(floor))

        // Lying still is not an event, so nearly every later step is silent
        // (the last few report the pair parting as the ball falls asleep).
        var quiet = 0
        for _ in 0 ..< 200 {
            world.step(dt: 1.0 / 60)
            if world.contacts.isEmpty { quiet += 1 }
        }
        #expect(quiet > 190)
    }

    /// The solver's own model, worth pinning because a sketch will meet it: a
    /// pile that settles goes to sleep, and sleeping bodies stop reporting
    /// contacts, so `touching` empties out under a still stack. The answer for
    /// "what is resting in this region" is a sensor, which stays awake (see
    /// `aSleepingBodyStaysInsideASensor` for the counterfactual).
    @Test func aSleepingPileStopsReportingItsTouches() {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(0, 0.6, 0), restitution: 0)
        let floor = try! #require(world.groundBody)

        run(world, steps: 20)
        #expect(crate.isAwake)
        #expect(crate.isTouching(floor))

        run(world, steps: 400)
        #expect(crate.isAwake == false)
        #expect(crate.touching.isEmpty)
        #expect(floor.touching.isEmpty)
        // It is still lying on the floor; only the reporting stopped.
        #expect(abs(crate.position.y - 0.5) < 0.02)
    }

    // MARK: Sensors

    /// The headline counterfactual: a ball dropped through a sensor sphere
    /// falls exactly as if nothing were there and reports going in and coming
    /// out, while the same sphere made solid stops it.
    @Test func aSensorReportsWhatPassesThroughAndSolidStops() {
        func drop(obstacle: Bool, sensing: Bool) -> (rest: Double, events: [Contact3D]) {
            let world = World3D()
            world.ground = 0
            var gate: Body3D?
            if obstacle {
                gate = world.addBody(.sphere(radius: 1), at: Vector3(0, 3, 0),
                                     kind: .static, isSensor: sensing)
            }
            let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 6, 0),
                                     restitution: 0)
            let seen = collect(world, steps: 240)
            let atGate = gate.map { g in seen.filter { $0.involves(g) && $0.involves(ball) } }
            return (ball.position.y, atGate ?? [])
        }

        let clear = drop(obstacle: false, sensing: false)
        let through = drop(obstacle: true, sensing: true)
        let blocked = drop(obstacle: true, sensing: false)

        // A sensor pushes nothing: the ball lands where it would have with an
        // empty scene.
        #expect(abs(through.rest - clear.rest) < 0.02)
        // The solid twin catches it well above the floor.
        #expect(blocked.rest > through.rest + 2)

        // Going in and coming out, in that order, once each.
        #expect(through.events.map(\.phase) == [.began, .ended])
        #expect(through.events[0].speed > 3)
        // The solid twin is struck rather than entered: it reports the hit and
        // the ball comes to rest on top of it, a body radius above its center.
        #expect(blocked.events.first?.phase == .began)
        #expect(blocked.rest > 4)
    }

    /// Why a sensor is kinematic and awake rather than the cheaper static kind:
    /// a body that settles inside one falls asleep, and a static sensor loses
    /// the contact the moment it does. The assert that the ball really is
    /// asleep is what makes this the counterfactual.
    @Test func aSleepingBodyStaysInsideASensor() {
        let world = World3D()
        world.ground = 0
        let plate = world.addBody(.box(width: 4, height: 0.5, depth: 4),
                                  at: Vector3(0, 0.5, 0), kind: .static,
                                  isSensor: true)
        let crate = world.addBody(.box(width: 0.6, height: 0.6, depth: 0.6),
                                  at: Vector3(0, 1.2, 0), restitution: 0)

        run(world, steps: 600)   // long enough to land, settle, and sleep
        #expect(crate.isAwake == false)
        #expect(plate.isTouching(crate))
        #expect(plate.touching.count == 1)
        #expect(crate.isTouching(plate))
    }

    /// A sensor is a region to be inside, not a surface to hit, so the ray the
    /// mouse picks with looks straight through it.
    @Test func aSensorIsTransparentToPicking() {
        func pick(sensing: Bool) -> Bool {
            let world = World3D()
            world.addBody(.box(width: 2, height: 2, depth: 2), at: Vector3(0, 0, 0),
                          kind: .static, isSensor: sensing)
            return world.raycast(from: Vector3(0, 0, 8), to: Vector3(0, 0, -8)) != nil
        }

        #expect(pick(sensing: false))       // the solid twin is hit
        #expect(pick(sensing: true) == false)
    }

    /// A sensor's motion type is its own: it never falls, and the `kind` setter
    /// leaves it alone rather than quietly turning it into a solid.
    @Test func aSensorHoldsItsPlaceAndItsKind() {
        let world = World3D()
        world.ground = 0
        let zone = world.addBody(.sphere(radius: 1), at: Vector3(0, 4, 0),
                                 isSensor: true)   // asked for the default .dynamic
        #expect(zone.kind == .kinematic)
        #expect(zone.isSensor)

        zone.kind = .dynamic
        #expect(zone.kind == .kinematic)

        run(world, steps: 240)
        #expect(abs(zone.position.y - 4) < 1e-6)   // gravity never touched it

        // And it can still be moved by hand, which is how a sensor follows
        // something.
        zone.position = Vector3(0, 2, 0)
        run(world, steps: 2)
        #expect(abs(zone.position.y - 2) < 1e-6)
    }

    // MARK: Touch bookkeeping

    @Test func enteredAndExitedNameTheStepsTransitions() {
        let world = World3D()
        world.ground = 0
        let zone = world.addBody(.sphere(radius: 1), at: Vector3(0, 3, 0),
                                 kind: .static, isSensor: true)
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 6, 0))

        var entered = 0
        var exited = 0
        for _ in 0 ..< 240 {
            world.step(dt: 1.0 / 60)
            entered += zone.entered.count
            exited += zone.exited.count
            // Occupancy and the transitions agree at every single step.
            #expect(zone.touching.contains { $0 === ball } == (entered > exited))
        }
        #expect(entered == 1)
        #expect(exited == 1)
        #expect(zone.touching.isEmpty)
    }

    /// A body taken out of the world leaves no trace in anyone's touch list,
    /// and the parting the solver reports a step later is dropped rather than
    /// handed over pointing at a body that no longer exists.
    @Test func aRemovedBodyLeavesNoStaleTouches() {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(0, 0.6, 0))
        let neighbor = world.addBody(.box(width: 1, height: 1, depth: 1),
                                      at: Vector3(1.02, 0.6, 0))
        // Removed while the pile is still awake and reporting.
        run(world, steps: 20)
        let floor = try! #require(world.groundBody)
        #expect(crate.isTouching(floor))

        world.remove(crate)
        run(world, steps: 5)
        #expect(floor.touching.contains { $0 === crate } == false)
        #expect(floor.touching.contains { $0 === neighbor })
        #expect(world.contacts.allSatisfy { !$0.involves(crate) })
    }

    // MARK: Determinism

    /// The listener records on whichever worker thread finishes first, so the
    /// buffer is put in pair order before it leaves the bridge: two identical
    /// worlds must read the same events in the same order.
    @Test func contactEventsReplayInTheSameOrder() {
        func runScene() -> [String] {
            let world = World3D()
            world.ground = 0
            for index in 0 ..< 8 {
                world.addBody(.box(width: 0.8, height: 0.8, depth: 0.8),
                              at: Vector3(Double(index % 3) * 0.85 - 0.85,
                                          1 + Double(index) * 0.9,
                                          Double(index % 2) * 0.4),
                              rotated: Double(index) * 0.17, axis: .unitZ)
            }
            var log: [String] = []
            for step in 0 ..< 200 {
                world.step(dt: 1.0 / 60)
                for contact in world.contacts {
                    let a = world.bodies.firstIndex { $0 === contact.a } ?? -1
                    let b = world.bodies.firstIndex { $0 === contact.b } ?? -1
                    log.append("\(step) \(contact.phase == .began ? "+" : "-") \(a):\(b)")
                }
            }
            return log
        }

        let first = runScene()
        #expect(first.count > 8)
        #expect(runScene() == first)
    }

    // MARK: A cloth's touches

    static let clothMesh = Mesh.plane(width: 2, depth: 2, segments: 10)

    /// A soft body reaches the same list, though the solver reports it through
    /// a channel of its own: a whole contact set per step and never a parting,
    /// diffed back into a began and an ended. Twin: the same sheet dropped
    /// where the floor is not.
    @Test func aClothLandingReportsWhatItLandedOn() throws {
        func drop(onto floor: Bool) throws -> (contacts: [Contact3D], landedOn: Bool) {
            let world = World3D()
            if floor { world.ground = 0 }
            let cloth = try #require(world.addSoftBody(from: Self.clothMesh,
                                                       at: Vector3(0, 2, 0)))
            let seen = collect(world, steps: 90).filter { $0.involves(cloth) }
            let onGround = seen.contains {
                $0.phase == .began && $0.other(than: cloth) === world.groundBody
            }
            return (seen, onGround)
        }
        #expect(try drop(onto: false).contacts.isEmpty,
                "nothing to land on, nothing to report")

        let landed = try drop(onto: true)
        #expect(landed.landedOn, "the cloth names the floor it came down on")
        let landing = try #require(landed.contacts.first { $0.phase == .began })
        #expect(abs(landing.point.y) < 0.05)         // touched at y = 0
        // Dropped 2 units: sqrt(2 * 9.8 * 2) is about 6.3 units/s.
        #expect(landing.speed > 4 && landing.speed < 9, "\(landing.speed)")
        #expect(abs(abs(landing.normal.y) - 1) < 0.01)
    }

    /// A settled cloth keeps its touch list where a settled pile of crates
    /// drops one. The difference is deliberate: the solver *reports* a rigid
    /// pair being removed, but it merely stops asking a sleeping soft body who
    /// it is against, and that is not the same as letting go.
    @Test func aSettledClothHoldsItsTouchesWhereASettledCrateDropsThem() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.clothMesh,
                                                   at: Vector3(0, 1, 0)))
        let crate = world.addBody(.box(width: 0.6, height: 0.6, depth: 0.6),
                                  at: Vector3(4, 1, 0))
        run(world, steps: 600)
        #expect(!cloth.isAwake && !crate.isAwake, "both have settled")
        #expect(cloth.touching.count == 1)
        #expect(cloth.isTouching(try #require(world.groundBody)))
        #expect(crate.touching.isEmpty, "the rigid rule, unchanged")
    }

    /// Taking the cloth off again reports the parting, so a began is always
    /// answered by an ended.
    @Test func liftingAClothOffReportsTheParting() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.clothMesh,
                                                   at: Vector3(0, 1, 0)))
        run(world, steps: 240)
        #expect(cloth.touching.count == 1)

        for vertex in 0 ..< Self.clothMesh.positions.count { cloth.pin(vertex) }
        var parted = false
        for _ in 0 ..< 60 {
            for vertex in 0 ..< Self.clothMesh.positions.count {
                cloth.move(vertex, to: cloth.positions[vertex] + Vector3(0, 0.05, 0))
            }
            world.step(dt: 1.0 / 60)
            if cloth.contacts.contains(where: { $0.phase == .ended }) { parted = true }
        }
        #expect(parted, "the ended event arrives as it comes off")
        #expect(cloth.touching.isEmpty)
    }

    /// A sensor sees a cloth the way it sees anything else. Twin: the same
    /// plate with nothing dropped through it.
    @Test func aSensorSeesAClothPassThrough() throws {
        func run(withCloth: Bool) throws -> Int {
            let world = World3D()
            world.ground = 0
            let plate = world.addBody(.box(width: 3, height: 0.3, depth: 3),
                                      at: Vector3(0, 0.6, 0), kind: .static,
                                      isSensor: true)
            if withCloth {
                _ = try #require(world.addSoftBody(from: Self.clothMesh,
                                                   at: Vector3(0, 2, 0)))
            }
            var seen = 0
            for _ in 0 ..< 120 {
                world.step(dt: 1.0 / 60)
                seen += plate.entered.count
            }
            return seen
        }
        #expect(try run(withCloth: false) == 0)
        #expect(try run(withCloth: true) >= 1, "the plate is crossed")
    }

    /// The soft half of the buffer replays like the rigid half: the diff walks
    /// its pairs in a fixed order and the drain sorts what leaves.
    @Test func aClothLogsTheSameContactsOnEveryRun() throws {
        func log() throws -> [String] {
            let world = World3D()
            world.ground = 0
            world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0.6, 0.5, 0),
                          kind: .static)
            _ = try #require(world.addSoftBody(from: Self.clothMesh, at: Vector3(0, 2, 0)))
            var lines: [String] = []
            for step in 0 ..< 200 {
                world.step(dt: 1.0 / 60)
                for contact in world.contacts {
                    lines.append("\(step) \(contact.phase) "
                                 + "\(String(format: "%.4f", contact.point.x))")
                }
            }
            return lines
        }
        let first = try log()
        #expect(!first.isEmpty)
        #expect(try log() == first)
    }
}
