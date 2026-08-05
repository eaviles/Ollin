import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the water tier: a world with `water` floats what is lighter
/// than it, sinks what is heavier, and puts the waterline where the displaced
/// volume says. Behavioral (the no-pixel-snapshot policy for physics), each one
/// pinned against a counterfactual twin: the same scene run twice with one
/// setting changed.
struct Buoyancy3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A world with a floor well below the surface, so a sinking body has
    /// somewhere to land and a floating one is nowhere near it.
    func pool(_ water: Water?) -> World3D {
        let world = World3D()
        world.ground = -10
        world.water = water
        return world
    }

    /// How much of a 1-unit cube is under the still surface.
    func submergedFraction(_ body: Body3D, level: Double = 0) -> Double {
        min(1, max(0, level - (body.position.y - 0.5)))
    }

    // MARK: What floats

    /// The headline: one number decides it, and it is the density the body was
    /// built with.
    @Test func aLightBodyFloatsWhereADenseOneSinks() {
        func settle(density: Double) -> Double {
            let world = pool(Water(level: 0))
            let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: density)
            run(world, steps: 600)
            return cube.position.y
        }
        let cork = settle(density: 0.3)
        let stone = settle(density: 3)
        #expect(cork > -0.5, "a body lighter than water should ride the surface")
        #expect(stone < -9, "a body heavier than water should reach the bottom")
    }

    /// A body only sinks because it is heavy, not because the water is missing:
    /// the same cork with no water at all goes straight down.
    @Test func withoutWaterTheSameBodyJustFalls() {
        func settle(_ water: Water?) -> Double {
            let world = pool(water)
            let cork = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: 0.3)
            run(world, steps: 600)
            return cork.position.y
        }
        #expect(settle(Water(level: 0)) > -0.5)
        #expect(settle(nil) < -9)
    }

    /// The waterline is not tuned, it is derived: a body of density d floats
    /// with fraction d of itself under. The margin is what sleeping costs,
    /// since the solver freezes the body wherever its last small oscillation
    /// had reached rather than at the exact equilibrium.
    @Test func theWaterlineSitsWhereTheDisplacedVolumeSays() {
        for density in [0.2, 0.4, 0.6, 0.8] {
            let world = pool(Water(level: 0))
            let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: density)
            run(world, steps: 2400)
            let submerged = submergedFraction(cube)
            #expect(abs(submerged - density) < 0.08,
                    "density \(density) floated with \(submerged) under")
        }
    }

    /// Water twice as heavy floats the same body twice as high.
    @Test func denserWaterFloatsTheSameBodyHigher() {
        func settle(waterDensity: Double) -> Double {
            let world = pool(Water(level: 0, density: waterDensity))
            let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: 0.6)
            run(world, steps: 2400)
            return submergedFraction(cube)
        }
        #expect(abs(settle(waterDensity: 1) - 0.6) < 0.08)
        #expect(abs(settle(waterDensity: 2) - 0.3) < 0.08)
    }

    // MARK: Drag

    /// Drag is what makes a dropped body settle instead of bobbing forever.
    /// Measured over the tail of a long run, so the initial splash is not
    /// counted either way.
    @Test func dragSettlesABodyThatOtherwiseKeepsBobbing() {
        func tailSwing(drag: Double) -> Double {
            let world = pool(Water(level: 0, linearDrag: drag, angularDrag: drag))
            let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: 0.5)
            var tail: [Double] = []
            for step in 0 ..< 3600 {
                world.step(dt: 1.0 / 60)
                if step >= 3480 { tail.append(cube.position.y) }
            }
            return (tail.max() ?? 0) - (tail.min() ?? 0)
        }
        #expect(tailSwing(drag: 0) > 0.2, "with no drag it should still be bobbing")
        #expect(tailSwing(drag: 0.5) < 0.01, "with drag it should have come to rest")
    }

    // MARK: Sleeping

    /// The failure mode this whole tier has to survive: a body that settles and
    /// falls asleep stops being pushed up, so it must not then sink.
    @Test func aFloaterThatFallsAsleepStaysAtItsWaterline() {
        let world = pool(Water(level: 0))
        let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(0, 0.5, 0), density: 0.5)
        run(world, steps: 1800)
        #expect(!cube.isAwake, "a floating body should settle and sleep")
        let settled = cube.position.y
        // Long enough that anything still sinking would be obvious.
        run(world, steps: 1800)
        #expect(abs(cube.position.y - settled) < 1e-6,
                "a sleeping floater must hold its waterline exactly")
        #expect(abs(submergedFraction(cube) - 0.5) < 0.08)
    }

    /// A tide has to reach a body that is already asleep, however far the new
    /// surface is from where it settled: the equilibrium moved, so the body has
    /// to be let go of.
    @Test func raisingTheLevelWakesABodyAsleepAtTheOldOne() {
        let world = pool(Water(level: 0))
        let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(0, 0.5, 0), density: 0.5)
        run(world, steps: 1800)
        #expect(!cube.isAwake)
        world.water?.level = 3
        run(world, steps: 900)
        #expect(abs(submergedFraction(cube, level: 3) - 0.5) < 0.08,
                "the cube should have risen to the new waterline")
    }

    /// Water added to a world that has already settled has to reach what is
    /// lying there asleep, the same way a tide does.
    @Test func addingWaterLaterFloatsWhatHadAlreadySettled() {
        let world = pool(nil)
        let cork = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(0, 2, 0), density: 0.4)
        run(world, steps: 1800)
        #expect(!cork.isAwake, "it should be asleep on the bottom")
        #expect(cork.position.y < -9)
        world.water = Water(level: 0)
        run(world, steps: 900)
        #expect(abs(submergedFraction(cork) - 0.4) < 0.08,
                "it should have surfaced and found its waterline")
    }

    /// A swell wakes what it washes over and leaves the bottom alone, which is
    /// what keeps a sunk pile from being stirred awake every step.
    @Test func aSwellCarriesWhatFloatsAndLetsTheBottomSleep() {
        let world = pool(Water(level: 0, waves: Water.Waves(amplitude: 0.4,
                                                            wavelength: 6)))
        let raft = world.addBody(.box(width: 1, height: 0.4, depth: 1),
                                 at: Vector3(0, 1, 0), density: 0.4)
        let stone = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(4, 1, 0), density: 4)
        run(world, steps: 600)
        var heights: [Double] = []
        for _ in 0 ..< 600 {
            world.step(dt: 1.0 / 60)
            heights.append(raft.position.y)
        }
        let swing = (heights.max() ?? 0) - (heights.min() ?? 0)
        #expect(swing > 0.2, "the raft should be riding the swell")
        #expect(stone.position.y < -9, "the stone should be on the bottom")
        #expect(!stone.isAwake, "a stone on the bottom should sleep through a swell")
    }

    /// Still water is a flat plane, so nothing bobs at all.
    @Test func stillWaterDoesNotBob() {
        let world = pool(Water(level: 0))
        let raft = world.addBody(.box(width: 1, height: 0.4, depth: 1),
                                 at: Vector3(0, 1, 0), density: 0.4)
        run(world, steps: 1200)
        var heights: [Double] = []
        for _ in 0 ..< 600 {
            world.step(dt: 1.0 / 60)
            heights.append(raft.position.y)
        }
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) < 0.01)
    }

    // MARK: The current, and the per-body knob

    @Test func aCurrentCarriesAFloaterDownstream() {
        func drift(flow: Vector3) -> Double {
            let world = pool(Water(level: 0, flow: flow))
            let raft = world.addBody(.box(width: 1, height: 0.4, depth: 1),
                                     at: Vector3(0, 1, 0), density: 0.4)
            run(world, steps: 600)
            return raft.position.x
        }
        #expect(abs(drift(flow: .zero)) < 0.5, "still water should carry nothing")
        #expect(drift(flow: Vector3(2, 0, 0)) > 5, "a current should carry it along")
    }

    /// The per-body override, both ways: enough of it floats a stone, none of
    /// it sinks a cork.
    @Test func perBodyBuoyancyOverridesWhatDensityAloneWouldDo() {
        func settle(density: Double, buoyancy: Double) -> Double {
            let world = pool(Water(level: 0))
            let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                     at: Vector3(0, 2, 0), density: density)
            cube.buoyancy = buoyancy
            run(world, steps: 900)
            return cube.position.y
        }
        #expect(settle(density: 3, buoyancy: 1) < -9)
        #expect(settle(density: 3, buoyancy: 6) > -0.5, "6x lift floats a stone")
        #expect(settle(density: 0.3, buoyancy: 1) > -0.5)
        #expect(settle(density: 0.3, buoyancy: 0) < -9, "no lift sinks a cork")
    }

    /// A stone lifted by exactly its own density ratio rides half under, the
    /// same as a body whose density says so: the override is a plain multiplier
    /// on what the water would otherwise do.
    @Test func perBodyBuoyancyMultipliesTheDensityRatio() {
        let world = pool(Water(level: 0))
        let cube = world.addBody(.box(width: 1, height: 1, depth: 1),
                                 at: Vector3(0, 2, 0), density: 3)
        cube.buoyancy = 6 // 6 x (1/3) = 2, so half of it should sit under
        run(world, steps: 2400)
        #expect(abs(submergedFraction(cube) - 0.5) < 0.08)
    }

    // MARK: What the water leaves alone

    /// A sensor is a detector, not a boat: the water must not push it off the
    /// spot the sketch put it on.
    @Test func aSensorInTheWaterIsNotFloated() {
        let world = pool(Water(level: 0))
        let sensor = world.addBody(.box(width: 1, height: 1, depth: 1),
                                   at: Vector3(0, -0.5, 0), isSensor: true)
        run(world, steps: 300)
        #expect(abs(sensor.position.y + 0.5) < 1e-6)
    }

    /// A soft body floats too, though nothing about it is the rigid path: the
    /// library's own buoyancy asserts on one, so each particle is pushed up on
    /// its own. Twins: the same sheet, one lighter than the water and one
    /// heavier.
    @Test func aLightClothFloatsWhereAHeavyOneSinks() throws {
        func drop(density: Double) throws -> Double {
            let world = pool(Water(level: 0))
            let cloth = try #require(
                world.addSoftBody(from: Mesh.plane(width: 2, depth: 2, segments: 8),
                                  at: Vector3(0, 3, 0), mass: 1, stiffness: 0.9))
            cloth.density = density
            run(world, steps: 900)
            return cloth.center.y
        }
        let raft = try drop(density: 0.3)
        let soaked = try drop(density: 4)
        #expect(abs(raft) < 0.3, "a light sheet lies in the surface: \(raft)")
        #expect(soaked < raft - 0.5, "a heavy one goes down: \(soaked)")
    }

    // MARK: What floats that has no pose

    static let sheet = Mesh.plane(width: 2, depth: 2, segments: 10)

    /// The waterline a raft settles at moves with how heavy it is, the same
    /// promise the rigid path makes, worked out particle by particle instead of
    /// from a displaced volume a sheet does not have.
    @Test func aRaftRidesHigherTheLighterItIs() throws {
        func settle(density: Double) throws -> Double {
            let world = pool(Water(level: 0))
            let raft = try #require(world.addSoftBody(from: Self.sheet,
                                                      at: Vector3(0, 1.5, 0),
                                                      mass: 2, stiffness: 0.9))
            raft.density = density
            run(world, steps: 900)
            return raft.center.y
        }
        let cork = try settle(density: 0.2)
        let heavier = try settle(density: 0.6)
        #expect(cork > heavier + 0.03, "\(cork) vs \(heavier)")
        #expect(cork < 0.4 && heavier > -0.4, "both are riding the surface")
    }

    /// A closed surface works its own density out from the mass and the volume
    /// it encloses, so a beach ball floats without being told anything. A sheet
    /// encloses nothing to work one out from, so it starts as heavy as water.
    @Test func aClosedSurfaceKnowsItsOwnDensity() throws {
        let world = pool(Water(level: 0))
        let ball = try #require(world.addSoftBody(from: Mesh.icosphere(radius: 0.5,
                                                                      subdivisions: 2),
                                                  at: Vector3(0, 1.5, 0), mass: 1,
                                                  pressure: 3))
        let cloth = try #require(world.addSoftBody(from: Self.sheet,
                                                   at: Vector3(4, 1.5, 0), mass: 2))
        // A 1 kg ball half a metre across is a balloon: light enough to ride
        // almost wholly out of the water.
        #expect(ball.density < 0.01)
        #expect(cloth.density == 1)
        run(world, steps: 600)
        #expect(ball.center.y > 0.25, "it sits on top: \(ball.center.y)")
    }

    /// The fix the first probe of this tier asked for. A sheet's area for its
    /// weight is enormous, so drag holds a sinking one below the solver's own
    /// sleep threshold and it would stall in mid water and read as floating.
    /// A body the water cannot hold up is kept going instead. Twin: the same
    /// sheet light enough to float, which does settle and sleep.
    @Test func aSinkingClothKeepsGoingWhereAFloatingOneSettles() throws {
        func fall(density: Double) throws -> (half: Double, full: Double, awake: Bool) {
            let world = pool(Water(level: 0))
            let cloth = try #require(world.addSoftBody(from: Self.sheet,
                                                       at: Vector3(0, 1, 0),
                                                       mass: 2, stiffness: 0.9))
            cloth.density = density
            run(world, steps: 600)
            let half = cloth.center.y
            run(world, steps: 600)
            return (half, cloth.center.y, cloth.isAwake)
        }
        let sinking = try fall(density: 4)
        #expect(sinking.full < sinking.half - 0.1,
                "still going down: \(sinking.half) then \(sinking.full)")

        let floating = try fall(density: 0.3)
        #expect(abs(floating.full - floating.half) < 0.02, "settled")
        #expect(!floating.awake, "and asleep at its waterline")
    }

    /// A swell carries a raft up and down with it, and a current takes it
    /// along. Twins: still water for the heave, no current for the drift.
    @Test func aSwellCarriesARaftAndACurrentDriftsIt() throws {
        func sail(waves: Water.Waves?, flow: Vector3) throws -> (heave: Double, drift: Double) {
            let world = pool(Water(level: 0, flow: flow, waves: waves))
            let raft = try #require(world.addSoftBody(from: Self.sheet,
                                                      at: Vector3(0, 0.6, 0),
                                                      mass: 2, stiffness: 0.9))
            raft.density = 0.3
            var low = Double.infinity, high = -Double.infinity
            for step in 0 ..< 600 {
                world.step(dt: 1.0 / 60)
                if step > 240 {
                    low = min(low, raft.center.y)
                    high = max(high, raft.center.y)
                }
            }
            return (high - low, raft.center.x)
        }
        let calm = try sail(waves: nil, flow: .zero)
        #expect(calm.heave < 0.02 && abs(calm.drift) < 0.2, "still water holds it still")

        let swell = try sail(waves: Water.Waves(amplitude: 0.4, wavelength: 8), flow: .zero)
        #expect(swell.heave > 0.3, "it rides the wave: \(swell.heave)")

        let carried = try sail(waves: nil, flow: Vector3(1, 0, 0))
        #expect(carried.drift > 5, "the current takes it: \(carried.drift)")
    }

    /// A pinned particle is held by whatever pinned it, so the water does not
    /// lift it: a sheet pegged along one edge above the surface stays pegged.
    @Test func theWaterDoesNotLiftPinnedParticles() throws {
        let world = pool(Water(level: 0))
        let flag = try #require(world.addSoftBody(from: Self.sheet, at: Vector3(0, 0.2, 0),
                                                  mass: 2, stiffness: 0.9,
                                                  pinned: { $0.z < -0.9 }))
        let pegged = flag.positions.enumerated()
            .filter { Self.sheet.positions[$0.offset].z < -0.9 }
        let before = pegged.map(\.element)
        run(world, steps: 600)
        let after = pegged.map { flag.positions[$0.offset] }
        #expect(zip(before, after).allSatisfy { ($0 - $1).length < 1e-6 })
    }

    // MARK: The surface a sketch draws

    /// Still water is flat, whatever it is asked.
    @Test func stillWaterIsFlatEverywhere() {
        let world = pool(Water(level: 2.5))
        #expect(world.waterHeight(at: Vector3(13, 0, -7)) == 2.5)
        #expect(world.waterHeight(at: .zero) == 2.5)
        let dry = pool(nil)
        #expect(dry.waterHeight(at: .zero) == nil)
    }

    /// The drawn surface and the ridden surface are the same function, which is
    /// the whole reason `waterMesh` exists rather than a sketch rolling its own
    /// waves: every vertex sits at the height the bodies are floating on.
    @Test func theDrawnSurfaceIsTheSurfaceTheBodiesRide() throws {
        let world = pool(Water(level: 0.5, waves: Water.Waves(amplitude: 0.3,
                                                              wavelength: 5)))
        run(world, steps: 37)
        let mesh = try #require(world.waterMesh(extent: 10, resolution: 8))
        for position in mesh.positions {
            let expected = try #require(world.waterHeight(at: position))
            #expect(abs(position.y - expected) < 1e-9)
        }
    }

    /// The wave normal is the analytic gradient, so it has to agree with the
    /// surface it claims to be tangent to.
    @Test func theWaveNormalMatchesTheSurfaceSlope() {
        let water = Water(level: 0, waves: Water.Waves(amplitude: 0.4,
                                                       wavelength: 3.5,
                                                       heading: 0.8))
        let step = 1e-5
        for point in [Vector3(0, 0, 0), Vector3(1.3, 0, -2.1), Vector3(-4, 0, 5)] {
            let normal = water.surface(at: point, phase: 1.7).normal
            let dx = (water.height(at: point + Vector3(step, 0, 0), phase: 1.7)
                      - water.height(at: point - Vector3(step, 0, 0), phase: 1.7))
                / (2 * step)
            let dz = (water.height(at: point + Vector3(0, 0, step), phase: 1.7)
                      - water.height(at: point - Vector3(0, 0, step), phase: 1.7))
                / (2 * step)
            let sampled = Vector3(-dx, 1, -dz).normalized
            #expect((normal - sampled).length < 1e-4)
        }
    }

    /// A swell of no amplitude is still water, exactly.
    @Test func aFlatSwellIsStillWater() {
        let water = Water(level: 1, waves: Water.Waves(amplitude: 0))
        #expect(water.height(at: Vector3(3, 0, 4), phase: 9) == 1)
    }

    // MARK: Determinism

    @Test func identicalRunsReplayIdentically() {
        func settle() -> [Vector3] {
            let world = pool(Water(level: 0, waves: Water.Waves(amplitude: 0.3,
                                                                wavelength: 5)))
            var bodies: [Body3D] = []
            for i in 0 ..< 6 {
                bodies.append(world.addBody(.box(width: 0.6, height: 0.6, depth: 0.6),
                                            at: Vector3(Double(i) * 0.7 - 2, 2, 0),
                                            density: 0.2 + Double(i) * 0.3))
            }
            run(world, steps: 400)
            return bodies.map(\.position)
        }
        #expect(settle() == settle())
    }
}
