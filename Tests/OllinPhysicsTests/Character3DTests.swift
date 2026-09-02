import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the walking character: it stands on what holds it, climbs
/// what its limits allow and is stopped by what they don't, jumps only from the
/// ground, rides what moves under it, and shows up among the ordinary bodies so
/// contacts and sensors can see it. Behavioral (the no-pixel-snapshot policy for
/// physics), each parameter pinned against a counterfactual twin: the same scene run
/// twice with one setting changed, so a passing test can't be explained by the
/// geometry alone. Parallel-safe like the rest of the 3D suite.
struct Character3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    // MARK: Standing

    @Test func standsOnTheGroundItLandsOn() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(0, 2, 0))
        run(world, steps: 90)

        #expect(walker.isOnGround)
        #expect(walker.groundState == .onGround)
        // The feet land on the floor, not the capsule's middle.
        #expect(abs(walker.position.y) < 0.05)
        #expect(abs(walker.groundNormal.y - 1) < 0.01)
        #expect(walker.groundBody === world.groundBody)
    }

    @Test func walkingOffAnEdgeFalls() {
        let world = World3D()
        // No ground: a narrow ledge to walk off the end of.
        world.addBody(.box(width: 2, height: 0.4, depth: 4), at: Vector3(0, -0.2, 0),
                      kind: .static)
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.3, 0))
        run(world, steps: 40)
        #expect(walker.isOnGround)

        walker.move(x: 2, z: 0)
        run(world, steps: 120)
        #expect(!walker.isOnGround)
        #expect(walker.groundState == .inAir)
        #expect(walker.groundBody == nil)
        #expect(walker.position.y < -2)          // falling freely
    }

    // MARK: Slopes

    /// Walk east up a ramp tilted `degrees` and report the height gained. The
    /// ramp is one static box rotated about z, so +x is uphill.
    func climbRamp(degrees: Double, maxSlope: Double? = nil) -> Double {
        let world = World3D()
        world.ground = -6
        let angle = degrees * .pi / 180
        world.addBody(.box(width: 12, height: 0.4, depth: 4), at: .zero,
                      kind: .static, rotated: angle, axis: Vector3(0, 0, 1))
        // Start above the ramp's lower half and let it settle onto the surface.
        let u = -3.0
        let start = Vector3(u * cos(angle) - 0.2 * sin(angle),
                            u * sin(angle) + 0.2 * cos(angle) + 0.6, 0)
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: start)
        if let maxSlope { walker.maxSlope = maxSlope }
        run(world, steps: 40)
        let settled = walker.position.y
        walker.move(x: 2, z: 0)
        run(world, steps: 180)
        return walker.position.y - settled
    }

    @Test func walksUpAGentleSlopeAndSlidesOffASteepOne() {
        // Well inside the default 50° limit: it climbs.
        #expect(climbRamp(degrees: 15) > 1)
        #expect(climbRamp(degrees: 25) > 1.5)
        // Well past it: nothing holds the character, and it ends up lower than
        // it started rather than higher.
        #expect(climbRamp(degrees: 70) < -1)
    }

    /// The sharper twin: one ramp, one parameter. The same 40° slope is walkable or
    /// not depending only on `maxSlope`, which is what proves the limit is
    /// doing the deciding rather than the geometry.
    @Test func theSlopeLimitIsWhatDecides() {
        let climbed = climbRamp(degrees: 40, maxSlope: 50 * Double.pi / 180)
        let refused = climbRamp(degrees: 40, maxSlope: 20 * Double.pi / 180)
        #expect(climbed > 1.5)
        #expect(refused < 0.2)
        #expect(climbed > refused + 1)
    }

    /// Just past the limit the slope still holds the character up, and that is
    /// what `.onSteepSlope` means. (Steeper still and nothing supports it at
    /// all: a near-vertical face reads `.notSupported`, since the character is
    /// touching something that cannot hold it rather than standing on it.)
    @Test func aSlopePastTheLimitReadsAsSteepGround() {
        let world = World3D()
        world.ground = -6
        let angle = 55 * Double.pi / 180
        world.addBody(.box(width: 12, height: 0.4, depth: 4), at: .zero,
                      kind: .static, rotated: angle, axis: Vector3(0, 0, 1))
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(-1.5, 2.4, 0))
        // Catch the frame where the slope is holding it: it is supported, but
        // not by anything it may walk on.
        var sawSteep = false
        for _ in 0 ..< 60 {
            world.advance(by: 1.0 / 60)
            if walker.groundState == .onSteepSlope { sawSteep = true }
        }
        #expect(sawSteep)
        #expect(walker.isSlopeTooSteep(Vector3(0, cos(angle), sin(angle))))
        #expect(!walker.isSlopeTooSteep(.unitY))
    }

    // MARK: Steps

    /// Walk east into a wide, deep block `blockHeight` tall (the only way past
    /// it is over it) and report the height actually gained.
    func climbStep(blockHeight: Double, stepHeight: Double) -> Double {
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 6, height: blockHeight, depth: 8),
                      at: Vector3(4, blockHeight / 2, 0), kind: .static)
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(0, 0.2, 0), stepHeight: stepHeight)
        run(world, steps: 40)
        let settled = walker.position.y
        walker.move(x: 2, z: 0)
        var peak = settled
        for _ in 0 ..< 240 {
            world.advance(by: 1.0 / 60)
            peak = max(peak, walker.position.y)
        }
        return peak - settled
    }

    @Test func stepsOntoALedgeUnderItsStepHeight() {
        // Comfortably inside the 0.4 limit: the character ends up on top.
        #expect(abs(climbStep(blockHeight: 0.3, stepHeight: 0.4) - 0.3) < 0.05)
        // Comfortably past it: the ledge is a wall.
        #expect(climbStep(blockHeight: 0.8, stepHeight: 0.4) < 0.05)
    }

    /// The twin that isolates the parameter: the very same 0.3 ledge is a step or a
    /// wall depending only on whether stepping is switched on.
    @Test func stepHeightZeroTurnsALedgeIntoAWall() {
        let stepped = climbStep(blockHeight: 0.3, stepHeight: 0.4)
        let blocked = climbStep(blockHeight: 0.3, stepHeight: 0)
        #expect(stepped > 0.25)
        #expect(blocked < 0.05)
    }

    // MARK: Jumping

    @Test func aJumpLeavesTheGround() {
        func peakHeight(jumping: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                            at: Vector3(0, 0.2, 0))
            run(world, steps: 40)
            var peak = walker.position.y
            if jumping { walker.jump() }
            for _ in 0 ..< 60 {
                world.advance(by: 1.0 / 60)
                peak = max(peak, walker.position.y)
            }
            return peak
        }
        let jumped = peakHeight(jumping: true)
        let stood = peakHeight(jumping: false)
        #expect(stood < 0.01)
        // v²/2g for the default 4 units/s is about 0.82.
        #expect(jumped > 0.6 && jumped < 1.0)
    }

    @Test func aJumpIsOnlyGrantedFromTheGround() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(0, 4, 0))
        // Falling, not standing: asking to jump changes nothing.
        world.advance(by: 1.0 / 60)
        #expect(!walker.isOnGround)
        let fallingSpeed = walker.velocity.y
        walker.jump()
        world.advance(by: 1.0 / 60)
        #expect(walker.velocity.y < fallingSpeed)   // still only accelerating down
        #expect(walker.position.y > 2)              // nowhere near a launch
    }

    // MARK: Pushing bodies

    /// Walk east into a crate and report how far the crate slid.
    func shove(crateDensity: Double, pushStrength: Double) -> Double {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 0.6, height: 0.6, depth: 0.6),
                                  at: Vector3(1.5, 0.3, 0), density: crateDensity)
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(0, 0.2, 0),
                                        pushStrength: pushStrength)
        run(world, steps: 40)
        let start = crate.position.x
        walker.move(x: 2, z: 0)
        run(world, steps: 240)
        return crate.position.x - start
    }

    @Test func shovesALightCrateUnlessItsStrengthIsZero() {
        // A 4 kg crate goes where it is pushed.
        #expect(shove(crateDensity: 0.02, pushStrength: 100) > 2)
        // The same crate, the same walk, no strength: it becomes a wall.
        #expect(abs(shove(crateDensity: 0.02, pushStrength: 0)) < 0.01)
    }

    @Test func aCrateTooHeavyForTheStrengthStaysPut() {
        // 43 kg on a friction-0.5 floor needs more than 100 N to start moving,
        // so the same push that shifted the light crate does nothing here.
        #expect(abs(shove(crateDensity: 0.2, pushStrength: 100)) < 0.01)
    }

    @Test func aCharacterCanBeBlockedByWhatItCannotPush() {
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 0.6, height: 0.6, depth: 4), at: Vector3(1.5, 0.3, 0),
                      density: 0.02)
        let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                        at: Vector3(0, 0.2, 0), pushStrength: 0)
        walker.move(x: 2, z: 0)
        run(world, steps: 120)
        // Stopped against the crate's near face rather than walking through it.
        #expect(walker.position.x < 1)
        // The two velocities part company here, which is the whole reason both
        // exist: it is still asking to walk at full pace, and getting nowhere.
        #expect(abs(walker.velocity.x - 2) < 0.01)
        #expect(abs(walker.actualVelocity.x) < 0.05)
    }

    @Test func onOpenGroundItActuallyMovesAtTheWalkingPace() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.2, 0))
        run(world, steps: 40)
        walker.move(x: 2, z: 0)
        run(world, steps: 60)
        // Nothing in the way, so intent and outcome agree.
        #expect(abs(walker.actualVelocity.x - 2) < 0.05)
        #expect(abs(walker.actualVelocity.y) < 0.05)
    }

    // MARK: Riding what moves

    @Test func aMovingPlatformCarriesTheCharacter() {
        let world = World3D()
        world.ground = -20
        let platform = world.addBody(.box(width: 4, height: 0.4, depth: 4), at: .zero,
                                     kind: .kinematic)
        platform.velocity = Vector3(1, 0, 0)
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.5, 0))
        run(world, steps: 30)
        let start = walker.position.x
        let platformStart = platform.position.x
        run(world, steps: 120)

        // Standing still relative to the platform: it moved exactly as far.
        let carried = walker.position.x - start
        #expect(abs(carried - (platform.position.x - platformStart)) < 0.05)
        #expect(carried > 1.9)
        #expect(abs(walker.groundVelocity.x - 1) < 0.05)
        #expect(walker.groundBody === platform)
    }

    // MARK: Presence among the bodies

    @Test func theCharacterHasAStandInAmongTheBodies() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.2, 0))
        // The stand-in is a body the world knows, but not one a drawing loop
        // over `bodies` would find (nobody asked for a capsule).
        #expect(!world.bodies.contains { $0 === walker.body })
        #expect(world.bodyByID[walker.body.id] === walker.body)
        #expect(world.characters.contains { $0 === walker })
    }

    @Test func walkingIntoASensorReportsIt() {
        let world = World3D()
        world.ground = 0
        let gate = world.addBody(.box(width: 1, height: 2, depth: 2), at: Vector3(2, 1, 0),
                                 isSensor: true)
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.2, 0))
        run(world, steps: 40)
        #expect(!gate.isTouching(walker.body))

        walker.move(x: 2, z: 0)
        var entered = false
        var reported = false
        for _ in 0 ..< 120 {
            world.advance(by: 1.0 / 60)
            if gate.isTouching(walker.body) { entered = true }
            if world.contacts.contains(where: { $0.involves(walker.body) }) {
                reported = true
            }
        }
        #expect(entered)
        #expect(reported)
        // A sensor never pushed it: the walk carried straight through.
        #expect(walker.position.x > 3)
    }

    // MARK: Teleporting, removal, replay

    @Test func teleportingRereadsWhatIsUnderfoot() {
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 4, height: 2, depth: 4), at: Vector3(20, 1, 0),
                      kind: .static)
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.2, 0))
        run(world, steps: 40)
        #expect(walker.groundBody === world.groundBody)

        // Onto the block, far away: the ground is re-read on the spot rather
        // than staying stale until the next step.
        walker.position = Vector3(20, 2, 0)
        #expect(walker.position.y > 1.9)
        #expect(walker.isOnGround)
        #expect(walker.groundBody !== world.groundBody)
    }

    @Test func removingACharacterTakesItsStandInWithIt() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0.2, 0))
        let innerID = walker.body.id
        run(world, steps: 20)

        world.remove(walker)
        #expect(world.characters.isEmpty)
        #expect(world.bodyByID[innerID] == nil)
        // The world keeps stepping with no character left in it.
        run(world, steps: 20)
        #expect(world.contacts.allSatisfy {
            world.identifier(of: $0.a) != innerID && world.identifier(of: $0.b) != innerID
        })
    }

    /// The 3D physics determinism rule: the same build replays a scene
    /// byte-identically, characters included.
    @Test func identicalRunsReplayIdentically() {
        func trace() -> [Vector3] {
            let world = World3D()
            world.ground = 0
            world.addBody(.box(width: 6, height: 0.3, depth: 8), at: Vector3(4, 0.15, 0),
                          kind: .static)
            let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                      at: Vector3(1.2, 0.25, 0), density: 0.02)
            let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                            at: Vector3(0, 1.2, 0))
            var poses: [Vector3] = []
            for i in 0 ..< 200 {
                walker.move(x: 2, z: 0)
                if i == 60 { walker.jump() }
                world.advance(by: 1.0 / 60)
                poses.append(walker.position)
                poses.append(crate.position)
            }
            return poses
        }
        #expect(trace() == trace())
    }
}
