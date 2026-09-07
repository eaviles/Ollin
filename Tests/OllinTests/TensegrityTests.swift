import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on `Tensegrity`: that the three built-in forms have the
/// member counts and lengths the literature gives them, that each one reads
/// as balanced by the equilibrium fit while a deliberately wrong twist does
/// not, and that the small geometry helpers do what they say. No GPU, no
/// solver.
@Suite
struct TensegrityTests {

    /// How many struts and how many cables meet at each node.
    private func degrees(_ t: Tensegrity) -> (struts: [Int], cables: [Int]) {
        var struts = [Int](repeating: 0, count: t.nodes.count)
        var cables = [Int](repeating: 0, count: t.nodes.count)
        for s in t.struts { struts[s.a] += 1; struts[s.b] += 1 }
        for c in t.cables { cables[c.a] += 1; cables[c.b] += 1 }
        return (struts, cables)
    }

    // MARK: The prism

    @Test func aPrismHasNStrutsAndThreeCablesPerStrut() {
        for n in [3, 4, 5, 6] {
            let prism = Tensegrity.prism(struts: n, radius: 1, height: 1.5)
            #expect(prism.nodes.count == 2 * n)
            #expect(prism.struts.count == n)
            #expect(prism.cables.count == 3 * n)
            let (s, c) = degrees(prism)
            #expect(s.allSatisfy { $0 == 1 }, "one strut ends at every node")
            #expect(c.allSatisfy { $0 == 3 }, "three cables hold every node")
            let lengths = prism.struts.map { prism.length(of: $0) }
            #expect(lengths.allSatisfy { abs($0 - lengths[0]) < 1e-12 }, "all struts alike")
        }
    }

    @Test func theBalancedTwistIsAQuarterTurnLessTheHalfAngle() {
        #expect(abs(Tensegrity.prismTwist(struts: 3) - .pi / 6) < 1e-12)     // 30°
        #expect(abs(Tensegrity.prismTwist(struts: 4) - .pi / 4) < 1e-12)     // 45°
        #expect(abs(Tensegrity.prismTwist(struts: 6) - .pi / 3) < 1e-12)     // 60°
        // Fewer than three struts is not a prism; the count is floored.
        #expect(Tensegrity.prismTwist(struts: 2) == Tensegrity.prismTwist(struts: 3))
        #expect(Tensegrity.prism(struts: 1).struts.count == 3)
    }

    @Test func theBuiltInPrismIsBalancedAndAWrongTwistIsNot() {
        for n in [3, 4, 6] {
            #expect(Tensegrity.prism(struts: n).imbalance < 1e-6, "\(n) struts")
        }
        // The twist does not depend on the proportions.
        #expect(Tensegrity.prism(struts: 3, radius: 2, height: 0.4).imbalance < 1e-6)
        #expect(Tensegrity.prism(struts: 3, radius: 0.3, height: 3).imbalance < 1e-6)
        // Any other twist leaves a force nothing can cancel.
        #expect(Tensegrity.prism(twist: 0.2).imbalance > 0.1)
        #expect(Tensegrity.prism(twist: 0.9).imbalance > 0.1)
        #expect(Tensegrity.prism(struts: 4, twist: 0.3).imbalance > 0.1)
    }

    // MARK: The six-strut form

    @Test func theIcosahedronHasSixStrutsInThreeParallelPairs() {
        let length = 2.0
        let ball = Tensegrity.icosahedron(strutLength: length)
        #expect(ball.nodes.count == 12)
        #expect(ball.struts.count == 6)
        #expect(ball.cables.count == 24)
        let (s, c) = degrees(ball)
        #expect(s.allSatisfy { $0 == 1 })
        #expect(c.allSatisfy { $0 == 4 }, "four cables at every node")
        for strut in ball.struts {
            #expect(abs(ball.length(of: strut) - length) < 1e-12)
        }
        // Every cable is the same length, the √6/4 of the strut Jessen's
        // icosahedron gives.
        for cable in ball.cables {
            #expect(abs(ball.length(of: cable) - length * 6.0.squareRoot() / 4) < 1e-12)
        }
        // Each strut has exactly one parallel partner, half a strut away.
        for strut in ball.struts {
            let (a, b) = ball.endpoints(of: strut)
            let direction = (b - a).normalized
            let partners = ball.struts.filter { other in
                guard other != strut else { return false }
                let (c, d) = ball.endpoints(of: other)
                return abs(abs((d - c).normalized.dot(direction)) - 1) < 1e-9
            }
            #expect(partners.count == 1)
            if let partner = partners.first {
                let (c, d) = ball.endpoints(of: partner)
                let across = (c + d) * 0.5 - (a + b) * 0.5
                #expect(abs(across.length - length / 2) < 1e-9)
            }
        }
        #expect(ball.center.length < 1e-12)
        #expect(ball.imbalance < 1e-6)
    }

    // MARK: The tower

    @Test func aTowerStacksPrismsOnSharedPolygonsWithAlternatingTwist() {
        let n = 3, levels = 4
        let mast = Tensegrity.tower(levels: levels, struts: n, radius: 1, levelHeight: 1.4)
        #expect(mast.nodes.count == n * (levels + 1))
        #expect(mast.struts.count == n * levels)
        #expect(mast.cables.count == n * (levels + 1) + n * levels)
        let (s, c) = degrees(mast)
        // The bottom and top polygons end one strut each; the shared ones two.
        #expect(s.prefix(n).allSatisfy { $0 == 1 })
        #expect(s.suffix(n).allSatisfy { $0 == 1 })
        #expect(s.dropFirst(n).dropLast(n).allSatisfy { $0 == 2 })
        #expect(c.prefix(n).allSatisfy { $0 == 3 })
        #expect(c.dropFirst(n).dropLast(n).allSatisfy { $0 == 4 })
        #expect(abs(mast.bottom) < 1e-12)
        // Each level turns the polygon above it the other way from the last.
        func turn(ofPolygon k: Int) -> Double {
            let node = mast.nodes[k * n]
            return atan2(node.z, node.x)
        }
        let twist = Tensegrity.prismTwist(struts: n)
        var expected = 0.0
        for k in 0 ..< levels {
            let delta = turn(ofPolygon: k + 1) - turn(ofPolygon: k)
            let sign: Double = k.isMultiple(of: 2) ? 1 : -1
            #expect(abs(delta - sign * twist) < 1e-9, "level \(k)")
            expected += sign * twist
        }
        _ = expected
        #expect(mast.imbalance < 1e-6)
    }

    // MARK: Small helpers

    @Test func theGeometryHelpersReadAndMove() {
        let prism = Tensegrity.prism(struts: 3, radius: 1, height: 2)
        let strut = prism.struts[0]
        let (a, b) = prism.endpoints(of: strut)
        #expect(a == prism.nodes[strut.a])
        #expect(b == prism.nodes[strut.b])
        #expect(abs(prism.length(of: strut) - a.distance(to: b)) < 1e-12)
        #expect(abs(prism.center.y - 1) < 1e-12)
        #expect(abs(prism.bottom) < 1e-12)

        let moved = prism.translated(by: Vector3(1, 2, 3))
        #expect(abs(moved.bottom - 2) < 1e-12)
        #expect((moved.center - (prism.center + Vector3(1, 2, 3))).length < 1e-12)
        #expect(moved.struts == prism.struts && moved.cables == prism.cables)

        let bigger = prism.scaled(by: 2)
        #expect(abs(bigger.length(of: strut) - 2 * prism.length(of: strut)) < 1e-12)

        let turned = prism.rotated(by: Rotation3D(angle: .pi / 2, axis: .unitZ))
        #expect(abs(turned.length(of: strut) - prism.length(of: strut)) < 1e-12)
        #expect(abs(turned.nodes[0].y - prism.nodes[0].x) < 1e-12, "x went to y")
        #expect(turned.imbalance < 1e-6, "balance does not depend on where it stands")

        #expect(Tensegrity.Member(1, 2) == Tensegrity.Member(1, 2))
        #expect(Tensegrity.Member(1, 2) != Tensegrity.Member(2, 1))
    }

    @Test func anEmptyOrMemberlessStructureReadsAsBalanced() {
        let empty = Tensegrity(nodes: [], struts: [], cables: [])
        #expect(empty.imbalance == 0)
        #expect(empty.center == .zero)
        #expect(empty.bottom == 0)
        let strutsOnly = Tensegrity(nodes: [Vector3(0, 0, 0), Vector3(0, 1, 0)],
                                    struts: [Tensegrity.Member(0, 1)], cables: [])
        #expect(strutsOnly.imbalance == 0)
    }
}
