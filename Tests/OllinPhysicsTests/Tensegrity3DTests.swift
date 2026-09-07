import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for tensegrities in the solver: a `Tensegrity` built as capsule
/// struts on `.cable` joints stands where its struts alone would fall, lands
/// with every cable taut, ties its levels where they meet, and finds the
/// balanced twist on its own when built at the wrong one. Behavioral (the
/// no-pixel-snapshot policy for physics), each answer pinned against a
/// counterfactual twin. Parallel-safe like the rest of the 3D suite.
struct Tensegrity3DTests {

    func run(_ world: World3D, seconds: Double, dt: Double = 1.0 / 60) {
        for _ in 0 ..< Int(seconds / dt) { world.advance(by: dt) }
    }

    /// A world with a floor and the structure standing `lift` above it.
    func standing(_ form: Tensegrity, lift: Double = 0.3,
                  prestress: Double = 0.02) -> (World3D, Tensegrity3D)? {
        let world = World3D()
        world.ground = 0
        guard let built = world.addTensegrity(form, at: Vector3(0, lift - form.bottom, 0),
                                              prestress: prestress) else { return nil }
        return (world, built)
    }

    /// The mean turn from each bottom node of a prism to the top node above
    /// it, read from the live nodes.
    func twist(of prism: Tensegrity3D, struts n: Int) -> Double {
        let nodes = prism.nodes
        var sum = 0.0
        for i in 0 ..< n {
            var delta = atan2(nodes[n + i].z, nodes[n + i].x) - atan2(nodes[i].z, nodes[i].x)
            while delta > .pi { delta -= .tau }
            while delta < -.pi { delta += .tau }
            sum += delta
        }
        return sum / Double(n)
    }

    // MARK: It stands

    /// The same six struts, once with their cables and once without. Only the
    /// cabled ones are still standing after the fall.
    @Test func aTensegrityStandsWhereItsStrutsAloneCollapse() throws {
        let prism = Tensegrity.prism(struts: 3, radius: 1, height: 1.5)
        let (world, whole) = try #require(standing(prism))
        let bare = Tensegrity(nodes: prism.nodes, struts: prism.struts, cables: [])
        let (twinWorld, loose) = try #require(standing(bare))
        let startTop = whole.top
        run(world, seconds: 6)
        run(twinWorld, seconds: 6)
        // The fall takes the whole lift off the top and nothing else.
        #expect(whole.top > (startTop - 0.3) * 0.95, "the cabled prism stands")
        #expect(loose.top < startTop * 0.3, "the loose struts lie on the floor")
        #expect(whole.struts.count == 3 && whole.cables.count == 9)
        #expect(loose.cables.isEmpty)
    }

    @Test func theIcosahedronLandsWithEveryCableTaut() throws {
        let ball = Tensegrity.icosahedron(strutLength: 1.6)
        let (world, built) = try #require(standing(ball))
        #expect(built.struts.count == 6)
        #expect(built.cables.count == 24)
        #expect(built.jointsBetweenStruts.isEmpty, "no two struts touch")
        let startTop = built.top
        run(world, seconds: 6)
        #expect(abs((startTop - built.top) - 0.3) < 0.05, "it dropped by the lift and kept its height")
        #expect(built.bottom > -0.02, "it stands on the floor")
        for index in 0 ..< built.cables.count {
            #expect(!built.isSlack(index, tolerance: 0.02), "cable \(index) is taut")
        }
        // A rigid strut cannot let a cable shorten to its prestressed length,
        // so every cable sits a little over it and none stretches far.
        let ratios = zip(built.cableLengths, built.cableRestLengths).map { $0 / $1 }
        #expect(ratios.allSatisfy { $0 > 0.99 && $0 < 1.05 })
        #expect(!built.isAwake, "and it has settled")
    }

    @Test func aTowerTiesItsLevelsWhereTheyMeet() throws {
        let mast = Tensegrity.tower(levels: 3, struts: 3, radius: 1, levelHeight: 1.4)
        let (world, built) = try #require(standing(mast))
        #expect(built.struts.count == 9)
        #expect(built.cables.count == 21)
        // Two shared polygons of three nodes, a ball joint at each.
        #expect(built.jointsBetweenStruts.count == 6)
        let startTop = built.top
        run(world, seconds: 8)
        #expect(built.top > (startTop - 0.3) * 0.9, "the mast stands")
        #expect(abs(built.center.x) < 0.2 && abs(built.center.z) < 0.2, "and does not walk off")
        // A shared node is read from one of its two struts, so the other's
        // tip sits a solver's position error away from it: small, and the
        // measure of how well the ball joints hold the levels together.
        let nodes = built.nodes
        var worstGap = 0.0
        for (index, strut) in built.source.struts.enumerated() {
            let body = built.struts[index]
            let half = built.source.length(of: strut) / 2
            let tipA = body.position + Vector3(0, -half, 0).rotated(by: body.rotation)
            let tipB = body.position + Vector3(0, half, 0).rotated(by: body.rotation)
            worstGap = max(worstGap, tipA.distance(to: nodes[strut.a]),
                           tipB.distance(to: nodes[strut.b]))
        }
        #expect(worstGap < 0.03, "the shared nodes hold within \(worstGap)")
    }

    /// A world with a mast in it, saved and loaded back, still has the mast
    /// as one structure: the same struts, cables, and shared joints, its
    /// nodes where they were, and the grouping running on.
    @Test func aTensegrityComesBackFromASnapshotAsOneStructure() throws {
        let (world, built) = try #require(standing(Tensegrity.tower(levels: 3)))
        run(world, seconds: 2)
        let nodesBefore = built.nodes

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-tensegrity-\(UUID().uuidString).physics")
        defer { try? FileManager.default.removeItem(at: url) }
        try world.save(to: url)

        let fresh = World3D()
        #expect(fresh.load(contentsOf: url))
        let back = try #require(fresh.tensegrities.first)
        #expect(fresh.tensegrities.count == 1)
        #expect(back.struts.count == 9 && back.cables.count == 21)
        #expect(back.jointsBetweenStruts.count == 6)
        #expect(back.source == built.source)
        #expect(back.cableRestLengths == built.cableRestLengths)
        let nodesAfter = back.nodes
        #expect(nodesAfter.count == nodesBefore.count)
        for (a, b) in zip(nodesBefore, nodesAfter) {
            #expect(a.distance(to: b) < 1e-6)
        }
        // Restored and captured again, the bytes settle and do not move.
        fresh.restore(fresh.snapshot())
        let settled = fresh.snapshot()
        fresh.restore(settled)
        #expect(fresh.snapshot() == settled)
        #expect(fresh.tensegrities.count == 1)
        // And it carries on standing.
        run(fresh, seconds: 4)
        #expect(try #require(fresh.tensegrities.first).top > 3.5)
    }

    /// Built at the wrong twist with its cables prestressed, a prism turns
    /// toward the balanced twist as it settles; built at the right one, it
    /// stays there.
    @Test func aPrismAtTheWrongTwistTurnsTowardTheBalancedOne() throws {
        let balanced = Tensegrity.prismTwist(struts: 3)
        let (wrongWorld, wrong) = try #require(standing(Tensegrity.prism(twist: 0.2)))
        let (rightWorld, right) = try #require(standing(Tensegrity.prism()))
        let wrongBefore = twist(of: wrong, struts: 3)
        #expect(abs(wrongBefore - 0.2) < 1e-6)
        run(wrongWorld, seconds: 8)
        run(rightWorld, seconds: 8)
        let wrongAfter = twist(of: wrong, struts: 3)
        #expect(abs(wrongAfter - balanced) < abs(wrongBefore - balanced) / 3,
                "it closed most of the gap: \(wrongAfter) toward \(balanced)")
        #expect(abs(twist(of: right, struts: 3) - balanced) < 0.1)
    }

    // MARK: The cable joint

    /// A cable and a rod between the same two bodies, pushed together: the
    /// cabled body comes freely, the rodded one is held. Pulled apart, both
    /// are stopped at the length.
    @Test func aCableHoldsItsLengthOneWayOnly() {
        func drift(_ kind: JointKind3D, push: Double) -> Double {
            let world = World3D()
            world.ground = nil
            world.gravity = .zero
            let post = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                     at: .zero, kind: .static)
            let bead = world.addBody(.sphere(radius: 0.1), at: Vector3(2, 0, 0))
            world.connect(post, bead, kind)
            bead.velocity = Vector3(push, 0, 0)
            run(world, seconds: 1)
            return bead.position.x
        }
        let cable = JointKind3D.cable(from: .zero, to: Vector3(2, 0, 0))
        let rod = JointKind3D.distance(from: .zero, to: Vector3(2, 0, 0))
        #expect(drift(cable, push: -1) < 1.2, "the cable lets the bead come in")
        #expect(abs(drift(rod, push: -1) - 2) < 0.05, "the rod holds it out")
        #expect(abs(drift(cable, push: 1) - 2) < 0.05, "the cable stops it at its length")
        #expect(abs(drift(rod, push: 1) - 2) < 0.05)
    }

    /// A cable shorter than its anchors' spacing starts taut and pulls them
    /// together, which is what a prestressed cable does.
    @Test func aShortCablePullsItsAnchorsTogether() {
        func spacing(length: Double?) -> Double {
            let world = World3D()
            world.ground = nil
            world.gravity = .zero
            let a = world.addBody(.sphere(radius: 0.1), at: Vector3(-1, 0, 0))
            let b = world.addBody(.sphere(radius: 0.1), at: Vector3(1, 0, 0))
            world.connect(a, b, .cable(from: a.position, to: b.position, length: length))
            run(world, seconds: 1)
            return a.position.distance(to: b.position)
        }
        #expect(abs(spacing(length: nil) - 2) < 1e-3, "at its spacing, nothing moves")
        #expect(abs(spacing(length: 1.5) - 1.5) < 0.05, "shorter, it draws them in")
    }

    // MARK: Reading it back

    @Test func aShovedFormMovesAsOneAndKeepsItsCablesTaut() throws {
        let ball = Tensegrity.icosahedron(strutLength: 1.6)
        let (world, built) = try #require(standing(ball, lift: 0.05))
        run(world, seconds: 3)
        let restTop = built.top
        built.applyImpulse(Vector3(6, 0, 0))
        run(world, seconds: 0.5)
        #expect(built.center.x > 0.02, "it moved")
        run(world, seconds: 5)
        #expect(built.top > restTop * 0.8, "and is still standing, on whichever face it rolled to")
        #expect((0 ..< built.cables.count).allSatisfy { !built.isSlack($0, tolerance: 0.02) })
        // A strut's nodes are read from the strut, so a moved node moves with it.
        let nodes = built.nodes
        for (index, strut) in built.source.struts.enumerated() {
            let body = built.struts[index]
            #expect(((nodes[strut.a] + nodes[strut.b]) * 0.5 - body.position).length < 1e-6)
        }
        let (start, end) = built.endpoints(of: built.source.cables[0])
        #expect(abs(start.distance(to: end) - built.cableLengths[0]) < 1e-9)
    }

    @Test func removingATensegrityTakesItsStrutsAndCables() throws {
        let (world, built) = try #require(standing(Tensegrity.tower(levels: 2)))
        let crate = world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(4, 2, 0))
        #expect(world.tensegrities.count == 1)
        #expect(world.bodies.count == 6 + 1)
        #expect(world.joints.count == 15 + 3)
        world.remove(built)
        #expect(world.tensegrities.isEmpty)
        #expect(world.bodies.count == 1 && world.bodies[0] === crate)
        #expect(world.joints.isEmpty)
        run(world, seconds: 1)
        #expect(crate.position.y < 2, "the world still runs")
    }

    @Test func aStructureWithNoUsableStrutIsRefused() {
        let world = World3D()
        let point = Tensegrity(nodes: [Vector3(0, 1, 0), Vector3(0, 1, 0)],
                               struts: [Tensegrity.Member(0, 1)], cables: [])
        #expect(world.addTensegrity(point) == nil)
        #expect(world.tensegrities.isEmpty && world.bodies.isEmpty)
    }

    /// A cable naming a node no strut reaches has nothing to hold onto, so it
    /// is left out rather than pinned to thin air; the rest are built.
    @Test func aCableWithNoStrutUnderItIsSkipped() throws {
        var prism = Tensegrity.prism()
        prism.nodes.append(Vector3(0, 4, 0))            // a node nothing ends on
        prism.cables.append(Tensegrity.Member(0, prism.nodes.count - 1))
        let (world, built) = try #require(standing(prism))
        #expect(built.cables.count == 9)
        #expect(built.cableRestLengths.count == 9)
        #expect(built.cableLengths.count == 9)
        run(world, seconds: 2)
        #expect(built.top > 1)
    }

    @Test func aTensegrityGoesToSleepOnceItHasSettled() throws {
        let (world, built) = try #require(standing(Tensegrity.icosahedron(strutLength: 1.6)))
        run(world, seconds: 4)
        #expect(!built.isAwake)
        built.wake()
        #expect(built.isAwake)
    }
}
