import Foundation
import Ollin
internal import CJolt

/// A `Tensegrity` given weight: its struts are capsule bodies in a `World3D`
/// and its cables are `.cable` joints between their tips, so the structure
/// falls, lands on its feet, and stands, and a shove sends a ripple through
/// every cable. Build one with `World3D.addTensegrity(_:at:…)`; draw it with
/// `drawTensegrity(_:)` or by walking `struts` and `cables` yourself.
///
/// ```swift
/// let ball = world.addTensegrity(Tensegrity.icosahedron(strutLength: 1.6),
///                                at: Vector3(0, 3, 0))
/// // each frame:
/// world.advance(by: deltaTime)
/// fill(.white)
/// drawTensegrity(ball)
/// ```
///
/// The struts are ordinary `Body3D`s, so `dragBodies(in:)` picks them up,
/// `contacts` names them, and `applyImpulse` on one shoves the whole form.
/// `nodes` reads the live node positions back from the struts, which is how
/// the cables are drawn where they are rather than where they started.
public final class Tensegrity3D {

    /// The world the structure lives in.
    unowned let world: World3D

    /// The geometry as built, in world coordinates: the nodes some strut
    /// reaches, the struts that became bodies, and the cables that became
    /// joints, in the same order as `struts` and `cables`. A strut of no
    /// length, a cable to a node no strut reaches, and that node itself are
    /// left out, so every member here has a live counterpart.
    public let source: Tensegrity

    /// The strut bodies, one per `source.struts` entry in the same order. Each
    /// is a capsule standing along its own y axis from node `a` to node `b`.
    public let struts: [Body3D]

    /// The cable joints, one per `source.cables` entry in the same order.
    public let cables: [Joint3D]

    /// The ball joints tying two struts together where they share a node (a
    /// `tower`'s polygons); empty for a form whose struts never touch.
    public let jointsBetweenStruts: [Joint3D]

    /// The length each cable was given, after `prestress`, in world units.
    public let cableRestLengths: [Double]

    /// Which strut carries each node, and where on it: the offset from the
    /// strut's center in its own frame (along its y axis).
    let anchors: [(strut: Int, offset: Vector3)]

    /// Regroup parts that already exist in the world (a snapshot's restore).
    init(world: World3D, source: Tensegrity, struts: [Body3D], cables: [Joint3D],
         jointsBetweenStruts: [Joint3D], cableRestLengths: [Double],
         anchors: [(strut: Int, offset: Vector3)]) {
        self.world = world
        self.source = source
        self.struts = struts
        self.cables = cables
        self.jointsBetweenStruts = jointsBetweenStruts
        self.cableRestLengths = cableRestLengths
        self.anchors = anchors
    }

    init?(world: World3D, structure: Tensegrity, position: Vector3,
          strutRadius: Double, prestress: Double, stiffness: Double,
          density: Double, friction: Double, group: CollisionGroup) {
        let placed = structure.translated(by: position)
        var anchors = [(strut: Int, offset: Vector3)?](repeating: nil, count: placed.nodes.count)
        var struts: [Body3D] = []
        var builtStruts: [Tensegrity.Member] = []
        for strut in placed.struts {
            guard placed.nodes.indices.contains(strut.a),
                  placed.nodes.indices.contains(strut.b) else { continue }
            let (a, b) = placed.endpoints(of: strut)
            let length = a.distance(to: b)
            guard length > 1e-9 else { continue }
            // Always longer than wide, so the capsule has a straight middle.
            let radius = min(max(strutRadius, 1e-4), length * 0.25)
            let direction = (b - a) * (1 / length)
            let turn = Rotation3D(from: .unitY, to: direction)
            let body = world.addBody(.capsule(height: length - 2 * radius, radius: radius),
                                     at: a.lerp(to: b, 0.5),
                                     rotated: turn.angle, axis: turn.axis,
                                     density: density, friction: friction,
                                     group: group)
            struts.append(body)
            builtStruts.append(strut)
            let half = length / 2
            if anchors[strut.a] == nil { anchors[strut.a] = (struts.count - 1, Vector3(0, -half, 0)) }
            if anchors[strut.b] == nil { anchors[strut.b] = (struts.count - 1, Vector3(0, half, 0)) }
        }
        guard !struts.isEmpty else { return nil }

        // A node no strut reaches has nothing to anchor a cable to, so such a
        // cable is skipped rather than pinned to thin air, and the node itself
        // is left out of what was built.
        var cables: [Joint3D] = []
        var builtCables: [Tensegrity.Member] = []
        var restLengths: [Double] = []
        let tighten = 1 - min(max(prestress, 0), 0.5)
        for cable in placed.cables {
            guard placed.nodes.indices.contains(cable.a),
                  placed.nodes.indices.contains(cable.b),
                  let anchorA = anchors[cable.a], let anchorB = anchors[cable.b],
                  anchorA.strut != anchorB.strut else { continue }
            let pointA = placed.nodes[cable.a]
            let pointB = placed.nodes[cable.b]
            let rest = pointA.distance(to: pointB) * tighten
            cables.append(world.connect(struts[anchorA.strut], struts[anchorB.strut],
                                        .cable(from: pointA, to: pointB, length: rest,
                                               stiffness: stiffness)))
            builtCables.append(cable)
            restLengths.append(rest)
        }

        // Where two struts end on one node, tie them there.
        var shared: [Joint3D] = []
        var endsAt = [[Int]](repeating: [], count: placed.nodes.count)
        for (built, strut) in builtStruts.enumerated() {
            endsAt[strut.a].append(built)
            endsAt[strut.b].append(built)
        }
        for (node, list) in endsAt.enumerated() where list.count > 1 {
            for other in list.dropFirst() {
                shared.append(world.connect(struts[list[0]], struts[other],
                                            .ball(at: placed.nodes[node])))
            }
        }

        // Renumber so the built geometry names only the nodes that exist.
        var newIndex = [Int](repeating: -1, count: placed.nodes.count)
        var nodes: [Vector3] = []
        var keptAnchors: [(strut: Int, offset: Vector3)] = []
        for (index, anchor) in anchors.enumerated() {
            guard let anchor else { continue }
            newIndex[index] = nodes.count
            nodes.append(placed.nodes[index])
            keptAnchors.append(anchor)
        }
        func renumbered(_ member: Tensegrity.Member) -> Tensegrity.Member {
            Tensegrity.Member(newIndex[member.a], newIndex[member.b])
        }

        self.world = world
        self.source = Tensegrity(nodes: nodes, struts: builtStruts.map(renumbered),
                                 cables: builtCables.map(renumbered))
        self.struts = struts
        self.cables = cables
        self.jointsBetweenStruts = shared
        self.cableRestLengths = restLengths
        self.anchors = keptAnchors
    }

    // MARK: Reading it back

    /// Where the nodes are now, read from the strut bodies.
    public var nodes: [Vector3] {
        anchors.map { anchor in
            let body = struts[anchor.strut]
            return body.position + anchor.offset.rotated(by: body.rotation)
        }
    }

    /// The two live node positions a member of `source` runs between.
    public func endpoints(of member: Tensegrity.Member) -> (start: Vector3, end: Vector3) {
        let current = nodes
        return (current[member.a], current[member.b])
    }

    /// How long each cable is right now, in `source.cables` order. A cable
    /// reading shorter than its rest length is slack.
    public var cableLengths: [Double] {
        let current = nodes
        return source.cables.map { current[$0.a].distance(to: current[$0.b]) }
    }

    /// Whether the cable at `index` has gone slack: shorter than the length
    /// it was given by more than `tolerance` of that length.
    public func isSlack(_ index: Int, tolerance: Double = 0.01) -> Bool {
        guard cableRestLengths.indices.contains(index) else { return false }
        return cableLengths[index] < cableRestLengths[index] * (1 - tolerance)
    }

    /// The mean position of the struts.
    public var center: Vector3 {
        var sum = Vector3.zero
        for strut in struts { sum += strut.position }
        return sum * (1 / Double(max(struts.count, 1)))
    }

    /// The lowest node's height right now.
    public var bottom: Double {
        nodes.map(\.y).min() ?? 0
    }

    /// The highest node's height right now.
    public var top: Double {
        nodes.map(\.y).max() ?? 0
    }

    /// Whether any strut is still moving.
    public var isAwake: Bool {
        struts.contains { $0.isAwake }
    }

    /// Wake every strut, so a change takes effect on a form that has settled.
    public func wake() {
        for strut in struts { strut.wake() }
    }

    /// Shove the whole structure: `impulse` is split evenly over the struts,
    /// so the form moves as one and the cables carry the rest.
    public func applyImpulse(_ impulse: Vector3) {
        let share = impulse * (1 / Double(max(struts.count, 1)))
        for strut in struts { strut.applyImpulse(share) }
    }
}
