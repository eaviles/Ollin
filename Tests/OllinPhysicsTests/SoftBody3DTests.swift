import Foundation
import simd
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the soft-body tier: a mesh becomes a surface of particles
/// that drapes and squashes, and every knob does what it says. Behavioral (the
/// no-pixel-snapshot policy for physics), each one pinned against a
/// counterfactual twin: the same scene run twice with one setting changed.
struct SoftBody3DTests {

    static let cloth = Mesh.plane(width: 2, depth: 2, segments: 12)
    static let ball = Mesh.icosphere(radius: 0.5, subdivisions: 2)

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    /// Every edge's length now, over its length in the rest mesh: 1 is
    /// inextensible, 1.2 is a fifth longer than it started.
    func meanStretch(_ body: SoftBody3D) -> Double {
        let mesh = body.sourceMesh
        let now = body.positions
        var total = 0.0
        var count = 0
        var i = 0
        while i + 2 < mesh.indices.count {
            let t = (Int(mesh.indices[i]), Int(mesh.indices[i + 1]), Int(mesh.indices[i + 2]))
            for (a, b) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] where a < b {
                let rest = (mesh.positions[b] - mesh.positions[a]).length
                guard rest > 1e-9 else { continue }
                total += (now[b] - now[a]).length / rest
                count += 1
            }
            i += 3
        }
        return count == 0 ? 1 : total / Double(count)
    }

    // MARK: Building one

    @Test func coincidentVerticesMergeIntoSharedParticles() throws {
        // A generator's box is flat shaded: every face carries its own copy of
        // each corner, so its triangles share no vertex index at all. Welding
        // is what turns that back into one connected surface, and without it
        // the body would come apart into loose triangles.
        let mesh = Mesh.box(size: 1)
        let world = World3D()
        let box = try #require(world.addSoftBody(from: mesh, at: Vector3(0, 2, 0)))
        #expect(mesh.positions.count == 24)
        #expect(box.particleCount == 8)
        #expect(box.positions.count == mesh.positions.count)
    }

    @Test func aClosedSurfaceIsRecognisedAndAnOpenOneIsNot() throws {
        let world = World3D()
        let sheet = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 2, 0)))
        let sphere = try #require(world.addSoftBody(from: Self.ball, at: Vector3(4, 2, 0)))
        #expect(!sheet.isClosed)
        #expect(sphere.isClosed)
    }

    @Test func theSimulatedMeshKeepsWhatTheSourceMeshCarried() throws {
        let world = World3D()
        world.ground = 0
        var source = Self.cloth
        source.material = MeshMaterial(baseColor: .crimson)
        let cloth = try #require(world.addSoftBody(from: source, at: Vector3(0, 2, 0)))
        run(world, steps: 30)
        let simulated = cloth.mesh
        #expect(simulated.indices == source.indices)
        #expect(simulated.uvs == source.uvs)
        #expect(simulated.material?.baseColor == source.material?.baseColor)
        #expect(simulated.positions.count == source.positions.count)
        #expect(simulated.normals.count == source.positions.count)
        // The simulation has moved it, so it must not still be the rest shape.
        #expect(simulated.positions[0].y < source.positions[0].y + 2)
    }

    @Test func aMeshWithNoUsableTriangleIsRefused() {
        let world = World3D()
        let degenerate = Mesh(positions: [.zero, .zero, .zero],
                              indices: [0, 1, 2])
        #expect(world.addSoftBody(from: degenerate, at: .zero) == nil)
        #expect(world.softBodies.isEmpty)
    }

    // MARK: Draping

    @Test func aPinnedSheetHangsWhereAFreeOneFalls() throws {
        let world = World3D()
        world.ground = 0
        let free = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0)))
        let hung = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(6, 3, 0),
                                                  pinned: { $0.z < -0.9 }))
        run(world, steps: 180)
        // The free sheet is on the floor; the hung one still reaches its pins.
        #expect(free.positions.map(\.y).max()! < 0.1)
        #expect(hung.positions.map(\.y).max()! > 2.9)
        // And it is a hanging sheet, not a rigid one: its far edge is well below.
        #expect(hung.positions.map(\.y).min()! < 2.0)
    }

    @Test func aClothDrapesOverWhatItLandsOn() throws {
        let world = World3D()
        world.ground = 0
        let obstacle = world.addBody(.sphere(radius: 0.6), at: Vector3(0, 0.6, 0),
                                     kind: .static)
        let cloth = try #require(
            world.addSoftBody(from: Mesh.plane(width: 3, depth: 3, segments: 14),
                              at: Vector3(0, 2, 0), vertexRadius: 0.02))
        run(world, steps: 240)
        let ys = cloth.positions.map(\.y)
        // It is held up over the sphere and hangs down to the floor around it,
        // which is exactly the shape a passed-through cloth could not have.
        #expect(ys.max()! > 1.15)
        #expect(ys.max()! < 1.35)
        #expect(ys.min()! < 0.1)
        // The obstacle is static, so the cloth landing on it moved nothing.
        #expect(abs(obstacle.position.y - 0.6) < 1e-6)
    }

    @Test func aSettledBodyGoesToSleep() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 0.5, 0)))
        run(world, steps: 300)
        #expect(!cloth.isAwake)
        cloth.wake()
        #expect(cloth.isAwake)
    }

    // MARK: Stiffness

    @Test func aStifferClothStretchesLessUnderTheSameLoad() throws {
        // Everything is measured before the world goes: a body outliving its
        // world reads back its rest shape, not its last one.
        func hang(stiffness: Double) throws -> Double {
            let world = World3D()
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0), mass: 2,
                                  stiffness: stiffness, pinned: { $0.z < -0.9 }))
            run(world, steps: 300)
            return meanStretch(cloth)
        }
        #expect(try hang(stiffness: 1) < 1.01)
        #expect(try hang(stiffness: 0.05) > 1.15)
    }

    @Test func stiffnessMeansTheSameAtAnyWeight() throws {
        // Compliance is meters per newton, so a fixed number would soften a
        // heavy cloth and do nothing to a light one. The knob is normalized by
        // the body's own weight, and this is what pins that.
        func stretch(mass: Double) throws -> Double {
            let world = World3D()
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0), mass: mass,
                                  stiffness: 0.2, pinned: { $0.z < -0.9 }))
            run(world, steps: 300)
            return meanStretch(cloth)
        }
        let light = try stretch(mass: 0.2)
        let heavy = try stretch(mass: 20)
        #expect(abs(light - heavy) < 0.01)
        #expect(light > 1.01)
    }

    @Test func aBendResistantSheetHoldsItselfFlatterThanALimpOne() throws {
        // Held only at its middle, a sheet with no fold resistance falls around
        // the pin like a handkerchief; one that resists folding stays a plate.
        func droop(bend: Double) throws -> Double {
            let world = World3D()
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0), bend: bend,
                                  pinned: { abs($0.x) < 0.1 && abs($0.z) < 0.1 }))
            run(world, steps: 300)
            return 3 - cloth.positions.map(\.y).min()!
        }
        #expect(try droop(bend: 0) > 1.2)
        #expect(try droop(bend: 1) < 0.6)
    }

    // MARK: Pressure

    @Test func aPressurizedBallKeepsAShapeALimpOneLoses() throws {
        func rest(pressure: Double) throws -> (height: Double, volume: Double) {
            let world = World3D()
            world.ground = 0
            let body = try #require(
                world.addSoftBody(from: Self.ball, at: Vector3(0, 1.5, 0), mass: 1,
                                  pressure: pressure))
            run(world, steps: 180)
            let ys = body.positions.map(\.y)
            return (ys.max()! - ys.min()!, body.volume)
        }
        let limp = try rest(pressure: 0)
        let firm = try rest(pressure: 3)
        // The ball is 1 unit across when round, so a limp one is visibly
        // flattened and a firm one is close to its own diameter again.
        #expect(limp.height < 0.7)
        #expect(firm.height > 0.8)
        #expect(firm.volume > limp.volume * 1.5)
    }

    @Test func pressureIsIgnoredOnAnOpenSheet() throws {
        // A sheet has no inside to fill, so the knob has nothing to act on and
        // must not quietly blow the cloth into a shape.
        func settled(pressure: Double) throws -> [Vector3] {
            let world = World3D()
            world.ground = 0
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 2, 0),
                                  pressure: pressure))
            run(world, steps: 120)
            return cloth.positions
        }
        let none = try settled(pressure: 0)
        let plenty = try settled(pressure: 5)
        #expect(none == plenty)
    }

    @Test func pressureIsLiveAndFirmerShovesHarder() throws {
        // The same soft ball dropped beside the same light crate: the one with
        // gas in it drives the crate further.
        func shove(pressure: Double) throws -> Double {
            let world = World3D()
            world.ground = 0
            let crate = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                      at: Vector3(0.25, 0.2, 0), density: 0.02)
            let body = try #require(
                world.addSoftBody(from: Mesh.icosphere(radius: 0.4, subdivisions: 2),
                                  at: Vector3(0, 1.6, 0), mass: 30))
            // Set live rather than at build time, which also pins that the
            // setter reaches the solver.
            body.pressure = pressure
            run(world, steps: 180)
            return crate.position.x
        }
        #expect(try shove(pressure: 3) > (try shove(pressure: 0)) + 0.05)
    }

    // MARK: Holding on to it

    @Test func pinningHoldsAParticleAndUnpinningReleasesIt() throws {
        let world = World3D()
        let mesh = Self.cloth
        let cloth = try #require(world.addSoftBody(from: mesh, at: Vector3(0, 3, 0)))
        let edge = mesh.positions.indices.filter { mesh.positions[$0].z < -0.9 }
        #expect(!edge.isEmpty)
        for index in edge { cloth.pin(index) }
        #expect(cloth.isPinned(edge[0]))
        run(world, steps: 120)
        #expect(cloth.positions.map(\.y).max()! > 2.9)

        for index in edge { cloth.unpin(index) }
        #expect(!cloth.isPinned(edge[0]))
        run(world, steps: 120)
        // Nothing holds it now, and there is no floor in this world.
        #expect(cloth.positions.map(\.y).max()! < 2.0)
    }

    @Test func aMovedParticleArrivesWhereItWasSent() throws {
        let world = World3D()
        let cloth = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0),
                                                    pinned: { $0.z < -0.9 }))
        let corner = try #require(cloth.nearestVertex(to: Vector3(1, 3, 1)))
        let target = Vector3(1, 3.5, 0.4)
        for _ in 0 ..< 90 {
            cloth.move(corner, to: target)
            world.advance(by: 1.0 / 60)
        }
        #expect((cloth.positions[corner] - target).length < 1e-3)
        // Moving it pinned it, and the sheet came with it rather than tearing
        // one particle away from the rest.
        #expect(cloth.isPinned(corner))
        let neighbors = cloth.positions.filter { ($0 - target).length < 0.35 }
        #expect(neighbors.count > 3)
    }

    @Test func aPushedBodyLeansIntoTheForce() throws {
        // The sheet hangs from its z = -1 edge, so a wind along +z holds it out
        // instead of letting it fall straight down. Impulses do not reach a
        // soft body (its velocity lives per particle, not per pose), so a force
        // is the only way to blow one about, and this pins that the path works.
        //
        // An unforced sheet swings for a long time, so the height is averaged
        // over the last second rather than read at one arbitrary step.
        func height(wind: Vector3) throws -> Double {
            let world = World3D()
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 3, 0), mass: 0.5,
                                  pinned: { $0.z < -0.9 }))
            var total = 0.0
            var samples = 0
            for step in 0 ..< 300 {
                cloth.applyForce(wind)
                world.advance(by: 1.0 / 60)
                if step >= 180 { total += cloth.position.y; samples += 1 }
            }
            return total / Double(samples)
        }
        let still = try height(wind: .zero)
        let blown = try height(wind: Vector3(0, 0, 40))
        #expect(blown > still + 0.3)
    }

    // MARK: Bookkeeping

    @Test func aRemovedBodyLeavesTheWorld() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 2, 0)))
        #expect(world.softBodies.count == 1)
        world.remove(cloth)
        #expect(world.softBodies.isEmpty)
        run(world, steps: 10)
    }

    @Test func emptyingTheWorldTakesTheSoftBodiesWithIt() throws {
        let world = World3D()
        world.ground = 0
        _ = try #require(world.addSoftBody(from: Self.cloth, at: Vector3(0, 2, 0)))
        world.removeAll()
        #expect(world.softBodies.isEmpty)
        run(world, steps: 10)
    }

    @Test func identicalRunsReplayIdentically() throws {
        func settle() throws -> [Vector3] {
            let world = World3D()
            world.ground = 0
            _ = world.addBody(.sphere(radius: 0.5), at: Vector3(0.2, 0.5, 0), kind: .static)
            let cloth = try #require(
                world.addSoftBody(from: Self.cloth, at: Vector3(0, 2, 0), bend: 0.3))
            run(world, steps: 150)
            return cloth.positions
        }
        #expect(try settle() == (try settle()))
    }
}
