//  Recreation after Gego (Gertrud Goldschmidt) - the Chorros, 1970 to 1971:
//  tall falls of aluminum and steel rods hooked end to end, hung from a point
//  in the ceiling and let down to the floor, first shown together at the Betty
//  Parsons Gallery in New York in 1971.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://post.moma.org/gegos-stream-no-7
//
//  An original Ollin interpretation, written from the works and from the
//  accounts of how they were made. Nothing was ported: the rods were cut,
//  their ends bent into loops, and the loops hooked one into the next by hand.

import Ollin
import OllinPhysics

/// A Chorro (Gego, 1970 to 1971). Rods hooked end to end into long falls,
/// all hung from one point, that come down to the floor and lie out across it
/// wherever they land. **Drag** a rod to take hold of it.
///
/// Chorro is a jet of water, a waterfall. Each of hers is a sheaf of rods,
/// most of them a hand's span to an arm's length, with their ends bent into
/// small loops so one hooks into the next; the falls hang from a plate at
/// the top, splay a little as they leave it, are tied together part of the
/// way down by short rods into rings and triangles, and then drop straight
/// until they reach the floor, where whatever is left over lies out. She
/// never decided how the ends would lie. The rods settled where they settled,
/// and every time the piece was hung it settled differently.
///
/// So the sketch builds that and lets it settle. Every rod is a rigid body
/// joined to the next at the loop, where the hook is a ball joint, and the
/// hook at the top is a small kinematic plate the air moves by a few
/// centimeters, slowly and never twice the same way, so the falls never quite
/// stop. `falls` is how many chains hang from the plate, `reach` how much rod
/// is in each, which decides how much of it ends up on the floor, and `tiers`
/// how many rings of short rods tie the falls together on the way down. Each
/// rod is drawn as a line, thinner and paler the further off it is, with a
/// dot at every hook and a loop at every free end, and the far rods are laid
/// down before the near ones.
@main
final class Chorro: Sketch {
    let world = World3D()

    /// How many falls hang from the plate.
    @Param(6 ... 28, step: 1, icon: "arrow.down") var falls = 16
    /// How much rod is in each fall, in meters. The plate is a little over
    /// four meters up, so anything past that lies on the floor.
    @Param(3.0 ... 6.2, icon: "ruler") var reach = 5.3
    /// How many rings of short rods tie the falls together on the way down.
    @Param(0 ... 3, step: 1, icon: "circle.hexagongrid") var tiers = 2
    /// How hard the air moves the plate, in centimeters of drift.
    @Param(0 ... 12, icon: "wind") var air = 3.0
    /// The turn of the eye around the piece, in degrees a second.
    @Param(-8 ... 8, icon: "camera.rotate") var orbit = 2.0

    /// Where the plate hangs, and the small ring on it the falls hook onto.
    let hang = Vector3(0, 4.05, 0)
    var ringRadius = 0.08
    /// A rod's thickness, and the lengths the rods were cut to.
    let rodRadius = 0.012
    let rodLengths = 0.45 ... 0.95

    let paper = Color(hex: 0xEDEAE3)
    let wire = Color(hex: 0x2A2A2C)
    let floorInk = Color(hex: 0xDBD7CF)
    let shadowInk = Color(hex: 0xB9B4AB)

    /// A hook: a place where rods meet, or a free end. Its position is read
    /// off the rod that owns it, at that rod's top or bottom loop.
    struct Node {
        var rod: Int
        var atTop: Bool
        var isFreeEnd: Bool
    }
    /// One rod: the body, its length loop to loop, and the hooks at its ends.
    struct Rod {
        var body: Body3D
        var length: Double
        var a: Int
        var b: Int
    }

    var plate: Body3D?
    var nodes: [Node] = []
    var rods: [Rod] = []
    /// The falls' top hooks, in the plate's own frame, and which node each is.
    var ringPoints: [Vector3] = []
    var fallTops: [Int] = []

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        world.gravity = Vector3(0, -9.81, 0)
        world.ground = 0
        hangTheRods()
    }

    // MARK: - The piece

    /// Cuts the rods, hooks them into falls, ties the falls together at the
    /// tiers, and hangs the whole thing from the plate.
    func hangTheRods() {
        ringRadius = max(0.08, Double(falls) * 0.028 / .tau)
        plate = world.addBody(.sphere(radius: 0.02), at: hang, kind: .kinematic)
        guard let plate else { return }

        var chains: [[Int]] = []     // each fall's hooks, top to bottom
        var chainRods: [[Int]] = []  // each fall's rods, top to bottom
        ringPoints = []
        fallTops = []
        for c in 0 ..< falls {
            let around = Double(c) / Double(falls) * .tau + random(-0.08, 0.08)
            let out = Vector3(cos(around), 0, sin(around))
            let ringPoint = out * ringRadius
            ringPoints.append(ringPoint)

            // A fall leaves the plate leaning out a little, and the lean eases
            // as it goes down. One in five stops short of the floor; the rest
            // are laid out along the floor from where they reach it, pointing
            // away from the plate, and the settling does the rest.
            let lean = random(0.10, 0.18)
            let total = random() < 0.2 ? random(2.2, 3.0) : reach * random(0.9, 1.06)
            var point = hang + ringPoint
            var top = nodes.count
            fallTops.append(top)
            nodes.append(Node(rod: rods.count, atTop: true, isFreeEnd: false))
            var hooks = [top]
            var chainRodIndices: [Int] = []
            var length = 0.0
            var previous = plate
            var anchor = point
            var along = out
            while true {
                let rodLength = random(rodLengths.lowerBound, rodLengths.upperBound)
                if length + rodLength > total && !chainRodIndices.isEmpty { break }
                let ease = max(0, 1 - length / 2.2)
                var direction = (Vector3(0, -1, 0) + out * lean * ease
                                 + Vector3(random(-0.03, 0.03), 0, random(-0.03, 0.03))).normalized
                let drop = point.y - rodRadius
                if drop < rodLength * 0.999 {
                    // This rod reaches the floor: it slants down to it, or lies
                    // along it if the last one already got there.
                    along = Vector3(along.x * cos(0.5) - along.z * sin(0.5), 0,
                                    along.x * sin(0.5) + along.z * cos(0.5)) * (random() < 0.5 ? 1 : -1)
                    along = (along + out * 0.6).normalized
                    let run = (rodLength * rodLength - drop * drop).squareRoot()
                    direction = (along * run + Vector3(0, -drop, 0)) / rodLength
                }
                let bottom = point + direction * rodLength
                let body = rodBody(from: point, to: bottom, length: rodLength, shortened: false)
                let rod = rods.count
                world.connect(previous, body, .ball(at: anchor))
                let low = nodes.count
                nodes.append(Node(rod: rod, atTop: false, isFreeEnd: true))
                rods.append(Rod(body: body, length: rodLength, a: top, b: low))
                chainRodIndices.append(rod)
                hooks.append(low)
                nodes[top].isFreeEnd = false
                previous = body
                anchor = bottom
                point = bottom
                top = low
                length += rodLength
            }
            chains.append(hooks)
            chainRods.append(chainRodIndices)
        }

        // The tiers: at each, a ring of short rods between neighboring falls,
        // each from a hook near that height to the nearest hook on the next
        // fall, and a second rod from there to the hook below on every other
        // gap, so the ring is a run of triangles rather than a loose polygon.
        for t in 0 ..< tiers {
            let height = hang.y * (1 - 0.22 * Double(t + 1))
            for c in 0 ..< falls {
                let next = (c + 1) % falls
                guard let here = nearestHook(chains[c], to: height),
                      let there = nearestHook(chains[next], to: position(of: here)) else { continue }
                tie(here, there)
                if c % 2 == 0, let below = hookBelow(chains[next], there) {
                    tie(here, below)
                }
            }
        }
    }

    /// The hook of a fall nearest a height, as it hangs before settling.
    func nearestHook(_ hooks: [Int], to height: Double) -> Int? {
        hooks.dropFirst().min { abs(position(of: $0).y - height) < abs(position(of: $1).y - height) }
    }

    /// The hook of a fall nearest a point.
    func nearestHook(_ hooks: [Int], to point: Vector3) -> Int? {
        hooks.dropFirst().min { (position(of: $0) - point).length < (position(of: $1) - point).length }
    }

    func hookBelow(_ hooks: [Int], _ hook: Int) -> Int? {
        guard let k = hooks.firstIndex(of: hook), k + 1 < hooks.count else { return nil }
        return hooks[k + 1]
    }

    /// A short rod hooked between two hooks of different falls. Nothing is
    /// tied with a rod longer than the longest she cut, two hooks are tied
    /// once, and a hook a tie reaches is no longer a free end.
    func tie(_ a: Int, _ b: Int) {
        let pa = position(of: a), pb = position(of: b)
        let length = (pb - pa).length
        guard length > rodRadius * 3, length <= rodLengths.upperBound,
              !rods.contains(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) })
        else { return }
        let body = rodBody(from: pa, to: pb, length: length, shortened: true)
        world.connect(rods[nodes[a].rod].body, body, .ball(at: pa))
        world.connect(rods[nodes[b].rod].body, body, .ball(at: pb))
        rods.append(Rod(body: body, length: length, a: a, b: b))
        nodes[a].isFreeEnd = false
        nodes[b].isFreeEnd = false
    }

    /// A capsule lying along the line from one hook to the other. A tie is
    /// cut a little short of both hooks so it does not sit inside the rods it
    /// hooks onto; a fall's own rods meet cap to cap at the hook.
    func rodBody(from a: Vector3, to b: Vector3, length: Double, shortened: Bool) -> Body3D {
        let direction = (b - a).normalized
        let height = max(length - (shortened ? 4 : 2) * rodRadius, 0.01)
        let up = Vector3(0, 1, 0)
        var axis = up.cross(direction)
        var angle = acos(max(-1, min(1, up.dot(direction))))
        if axis.length < 1e-6 {
            axis = Vector3(1, 0, 0)
            angle = direction.y < 0 ? .pi : 0
        } else {
            axis = axis.normalized
        }
        return world.addBody(.capsule(height: height, radius: rodRadius),
                             at: (a + b) / 2, rotated: angle, axis: axis,
                             density: 2.7, friction: 0.5, checksPath: true)
    }

    /// Where a hook is now, read off the rod that owns it, or off the plate
    /// for a fall's top hook.
    func position(of node: Int) -> Vector3 {
        let n = nodes[node]
        let rod = rods[n.rod]
        if n.atTop, let plate, let fall = fallTops.firstIndex(of: node) {
            return plate.position + ringPoints[fall]
        }
        // The capsule's own axis runs from its top hook to its bottom one.
        let half = Vector3(0, rod.length / 2, 0).rotated(by: rod.body.rotation)
        return rod.body.position + (n.atTop ? -half : half)
    }

    // MARK: - Drawing

    override func draw() {
        background(paper)
        let turn = .degrees(orbit) * time
        camera(.perspective(eye: Vector3(sin(turn) * 6.6, 2.0, cos(turn) * 6.6),
                            target: Vector3(0, 2.0, 0), fieldOfView: .degrees(44)))

        moveTheAir()
        dragBodies(in: world)
        world.advance(by: deltaTime)

        drawFloor()
        drawRods()
        drawText("drag a rod", width / 2, height - 44, size: 15,
                 color: wire.withAlpha(0.5), align: .center, .bottom)
    }

    /// The air in the room: the plate drifts a few centimeters sideways,
    /// slowly and never twice the same way, and every fall hangs from it.
    func moveTheAir() {
        guard let plate else { return }
        let drift = air / 100
        let wander = Vector3(signedNoise(time * 0.21 + 3), 0, signedNoise(time * 0.17 + 9))
        plate.position = hang + wander * drift
    }

    /// The floor, and the shadow each rod throws on it from a lamp high up
    /// and a little to one side: what tells you which rods are lying down.
    func drawFloor() {
        let corners = [Vector3(-7, 0, -7), Vector3(7, 0, -7), Vector3(7, 0, 7), Vector3(-7, 0, 7)]
        let flat = corners.compactMap { project($0) }
        if flat.count == 4 {
            noStroke()
            fill(floorInk)
            drawPolygon(flat)
        }
        let lamp = Vector3(0.32, -1, 0.22).normalized
        noFill()
        stroke(shadowInk.withAlpha(0.55))
        strokeWeight(0.9)
        strokeCap(.round)
        for rod in rods {
            let a = position(of: rod.a), b = position(of: rod.b)
            guard let sa = project(a - lamp * (a.y / lamp.y)),
                  let sb = project(b - lamp * (b.y / lamp.y)) else { continue }
            drawLine(sa, sb)
        }
    }

    /// The rods as line work, far to near, with a dot at every hook and a
    /// loop at every free end, each sized by how far off it is.
    func drawRods() {
        guard let eye = activeCamera?.eye, let plate else { return }
        let points = nodes.indices.map { position(of: $0) }
        let flat = points.map { project($0) }
        let depth = points.map { ($0 - eye).length }
        // Wide enough that nothing in the room reaches either end, so a dot's
        // size still says exactly how far off it is.
        let near = 5.0, far = 10.0

        // The wire the plate hangs from, up out of the picture.
        if let low = project(plate.position), let high = project(plate.position + Vector3(0, 3, 0)) {
            noFill()
            stroke(shadowInk)
            strokeWeight(0.8)
            drawLine(low, high)
        }

        let order = rods.indices.sorted {
            depth[rods[$0].a] + depth[rods[$0].b] > depth[rods[$1].a] + depth[rods[$1].b]
        }
        noFill()
        strokeCap(.round)
        for k in order {
            let rod = rods[k]
            guard let a = flat[rod.a], let b = flat[rod.b] else { continue }
            let d = (depth[rod.a] + depth[rod.b]) / 2
            let t = clamp(map(d, near, far, 0, 1), 0, 1)
            strokeWeight(lerp(1.8, 0.6, t))
            stroke(wire.withAlpha(lerp(0.95, 0.3, t)))
            drawLine(a, b)
        }

        for (n, point) in flat.enumerated() {
            guard let point else { continue }
            let t = clamp(map(depth[n], near, far, 0, 1), 0, 1)
            let radius = lerp(2.2, 0.8, t)
            if nodes[n].isFreeEnd {
                noFill()
                stroke(wire.withAlpha(lerp(0.9, 0.25, t)))
                strokeWeight(lerp(1.2, 0.5, t))
                drawCircle(center: point, radius: radius)
            } else {
                noStroke()
                fill(wire.withAlpha(lerp(0.9, 0.25, t)))
                drawCircle(center: point, radius: radius)
            }
        }
    }
}
