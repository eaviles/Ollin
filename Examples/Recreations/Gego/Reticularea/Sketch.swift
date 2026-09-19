//  Recreation after Gego (Gertrud Goldschmidt) - the Reticulárea, first hung in
//  June 1969 in Sala 8 of the Museo de Bellas Artes, Caracas: an environment of
//  stainless steel and aluminum wire, modules with a triangular base tied to
//  one another by hand, spanning the ceiling and coming down the walls.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.macba.cat/en/obra/r4344-reticularea/
//
//  An original Ollin interpretation, written from the works, from her own
//  account of what she made, and from the accounts of how she made it. Nothing
//  was ported: the nets were bent, twisted and tied by hand in her Caracas
//  studio, without a weld anywhere in them.

import Ollin
import OllinPhysics

/// The Reticulárea (Gego, 1969 to 1982). A net of wire hung from the ceiling at
/// a handful of points, drooping between them into the room. **Drag** a wire to
/// take hold of it; it hangs from your hand until you let go.
///
/// Gego trained as an architect and spent her life among people making a very
/// orderly kind of geometric art, and the net is what she did instead. There is
/// no module repeated here, no center, and no row: the triangles are all
/// different sizes and all different shapes, and which of them is missing is as
/// much of the work as which of them is there. The parts of it are lines, and
/// a line has no inside, so what you are looking at is closer to a drawing that
/// happens to be standing up in the air than to a sculpture.
///
/// So the net is built the way that description asks for rather than as a grid.
/// `nodes` points are scattered by `stipple`, which spreads them evenly and
/// then lets a density pull them into knots and clearings, and `delaunay` joins
/// each one to its neighbors. Every triangle that comes out is kept unless it
/// is too big for a hand to have tied it or unless the opening rule takes it
/// away, and what is left is a fabric of triangles with holes torn through it
/// and an edge that frays instead of stopping. Those triangles are handed
/// straight to `World3D.addSoftBody`, so the wires that are drawn and the wires
/// the simulation holds are one and the same set: nothing invisible is holding
/// the net up.
///
/// It is hung by eight ties: the vertex nearest each one is carried to it and
/// held, six of them on the ceiling and two a meter below it out at the sides,
/// and gravity does the rest. The air in the room moves the ties a few
/// centimeters, slowly and never twice the same way, which is enough to keep
/// the whole net breathing. There is no surface to shade, so each wire is drawn
/// as a line on the canvas through `project`, thinner and paler the further it
/// is from the eye, with the far wires laid down before the near ones. Each
/// node carries a dot: her wires are tied, not welded, and a tie is a thing you
/// can see.
@main
final class Reticularea: Sketch {
    let world = World3D()
    var net: SoftBody3D?
    var grip: SoftGrip?

    /// How many points the net is built on. More of them is a finer net of
    /// smaller triangles, not a bigger one.
    @Param(150 ... 480, step: 10, icon: "point.3.connected.trianglepath.dotted")
    var nodes = 320
    /// How much of the net is taken away: at nought a whole fabric of
    /// triangles, further up a net with more and more torn out of it.
    @Param(0 ... 0.5, icon: "circle.dotted") var openings = 0.18
    /// How hard the air moves in the room, in centimeters of drift at the ties.
    @Param(0 ... 12, icon: "wind") var air = 4.0
    /// The turn of the eye around the room, in degrees a second.
    @Param(-8 ... 8, icon: "camera.rotate") var orbit = 2.4

    // The room the net hangs in, in meters. There is a good deal more net than
    // the ties are spread over, and that slack is what makes it hang in folds
    // and come down the walls instead of stretching flat like a canopy.
    let span = Vector2(9.0, 7.2)
    let ceiling = 3.35

    let paper = Color(hex: 0xEDEAE3)
    let wire = Color(hex: 0x2A2A2C)

    /// Every wire of the net, as a pair of vertices of the mesh handed to the
    /// simulation. This is the drawing and the structure at once.
    var wires: [(Int, Int)] = []
    /// Where each tie holds the net, and which vertex it holds.
    var ties: [(vertex: Int, at: Vector3)] = []

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        world.gravity = Vector3(0, -9.81, 0)
        hangTheNet()
    }

    // MARK: - The net

    /// Scatters the points, joins them, tears the holes, and hangs what is left
    /// from its ties.
    func hangTheNet() {
        let bounds = Rectangle(center: .zero, width: span.x, height: span.y)

        // Points spread evenly and then pulled about: the density is a slow
        // noise, so the net knots up in places and opens out in others the way
        // a thing tied by hand over several weeks does.
        let sites = stipple(count: nodes, in: bounds, iterations: 8) { p in
            0.35 + 0.65 * pow(noise(p.x * 0.34 + 11, p.y * 0.34 - 7), 1.6)
        }

        // Every point joined to its neighbors. What comes back fills the
        // convex hull of the scatter, which is a shape no hand would make, so
        // the triangles that are too big to have been tied are dropped: that
        // takes the long slivers along the hull with it and leaves an edge that
        // frays.
        let joined = delaunay(sites)
        let reach = (span.x * span.y / Double(nodes)).squareRoot() * 1.55

        var kept: [(Int, Int, Int)] = []
        var i = 0
        while i + 2 < joined.indices.count {
            let a = joined.indices[i], b = joined.indices[i + 1], c = joined.indices[i + 2]
            i += 3
            let pa = sites[a], pb = sites[b], pc = sites[c]
            let longest = max((pb - pa).length, max((pc - pb).length, (pa - pc).length))
            if longest > reach { continue }

            // The openings. Judged on where the triangle sits rather than on a
            // throw of the dice, so a hole is a region of the net that was left
            // out and not a scatter of gaps.
            let mid = (pa + pb + pc) / 3
            if noise(mid.x * 0.52 - 3, mid.y * 0.52 + 19) < openings { continue }
            kept.append((a, b, c))
        }

        // The points no surviving triangle uses are gone with them.
        var index = [Int: Int]()
        var positions: [Vector3] = []
        var indices: [UInt32] = []
        for (a, b, c) in kept {
            for corner in [a, b, c] {
                if index[corner] == nil {
                    index[corner] = positions.count
                    positions.append(Vector3(sites[corner].x, 0, sites[corner].y))
                }
                indices.append(UInt32(index[corner]!))
            }
        }
        guard positions.count > 3 else { return }

        var seen = Set<Int64>()
        wires = []
        for k in stride(from: 0, to: indices.count, by: 3) {
            let t = (Int(indices[k]), Int(indices[k + 1]), Int(indices[k + 2]))
            for (u, v) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] {
                let low = min(u, v), high = max(u, v)
                let key = Int64(low) << 32 | Int64(high)
                if seen.insert(key).inserted { wires.append((low, high)) }
            }
        }

        let mesh = Mesh(positions: positions, indices: indices)
        net = world.addSoftBody(from: mesh, at: Vector3(0, ceiling, 0),
                                mass: 1.1, stiffness: 0.96, bend: 0.02,
                                damping: 0.22, friction: 0.4, iterations: 8,
                                vertexRadius: 0.004, isTwoSided: true)
        tieItUp()
    }

    /// The points the net is tied at. Six on the ceiling, scattered rather
    /// than ranked, and two a meter below it out at the far sides, which is
    /// what pulls the net down out of the ceiling and into the room.
    func tieItUp() {
        guard let net else { return }
        let points = [
            Vector3(-1.95, ceiling, -1.45), Vector3(0.35, ceiling, -1.75),
            Vector3(2.15, ceiling, -0.45), Vector3(-1.25, ceiling, 1.15),
            Vector3(1.05, ceiling, 1.65), Vector3(-0.15, ceiling, -0.25),
            Vector3(-3.35, 2.15, -2.65), Vector3(3.25, 2.55, -2.75),
        ]
        var taken = Set<Int>()
        ties = []
        for point in points {
            // The tie holds whichever vertex is nearest where it hangs, read
            // against the flat net rather than the settled one, and no vertex
            // is asked to be in two places at once.
            guard let vertex = net.nearestVertex(to: Vector3(point.x, ceiling, point.z)),
                  taken.insert(vertex).inserted else { continue }
            ties.append((vertex, point))
        }
    }

    // MARK: - Input

    override func mousePressed() {
        grip = grabSoftBody(at: mouse, in: world)
    }

    override func mouseReleased() {
        if let grip { releaseSoftGrip(grip) }
        grip = nil
    }

    // MARK: - Drawing

    override func draw() {
        background(paper)
        let turn = .degrees(orbit) * time
        camera(.perspective(eye: Vector3(sin(turn) * 9.9, 1.35, cos(turn) * 9.9),
                            target: Vector3(0, 2.3, 0), fieldOfView: .degrees(44)))

        moveTheAir()
        if let grip { dragSoftGrip(grip, to: mouse) }
        world.advance(by: deltaTime)

        drawNet()
        drawText("drag a wire", width / 2, height - 44, size: 15,
                 color: wire.withAlpha(0.5), align: .center, .bottom)
    }

    /// The air in the room. Each tie is carried to its point plus a slow drift
    /// of its own, so the net is never still and never repeats: a tie is what
    /// the net hangs from, so moving the ties moves everything under them.
    func moveTheAir() {
        guard let net else { return }
        let drift = air / 100
        for (n, tie) in ties.enumerated() {
            let phase = Double(n) * 13.7
            let wander = Vector3(signedNoise(time * 0.21 + phase),
                                 signedNoise(time * 0.17 + phase + 5) * 0.4,
                                 signedNoise(time * 0.19 + phase + 9))
            net.move(tie.vertex, to: tie.at + wander * drift)
        }
    }

    /// The net drawn as line work. There is no surface here to shade and
    /// nothing hides anything: what carries the depth is how thin and how pale
    /// a wire goes as it runs away from the eye, and that the near wires are
    /// laid down over the far ones.
    func drawNet() {
        guard let net, let eye = activeCamera?.eye else { return }
        let points = net.positions
        guard points.count > 3 else { return }

        let flat = points.map { project($0) }
        let depth = points.map { ($0 - eye).length }
        // The two distances the depth cue runs between. They are set wide
        // enough that nothing in the room reaches either end of them, so a
        // wire's weight and a node's size still say exactly how far off it is
        // at the very front and the very back of the net.
        let near = 5.0, far = 15.5

        // Far to near, so a wire in front of another is drawn over it.
        let order = wires.sorted {
            depth[$0.0] + depth[$0.1] > depth[$1.0] + depth[$1.1]
        }
        noFill()
        strokeCap(.round)
        for (u, v) in order {
            guard let a = flat[u], let b = flat[v] else { continue }
            let d = (depth[u] + depth[v]) / 2
            let t = clamp(map(d, near, far, 0, 1), 0, 1)
            strokeWeight(lerp(1.7, 0.55, t))
            stroke(wire.withAlpha(lerp(0.95, 0.24, t)))
            drawLine(a, b)
        }

        // The ties. Gego bent the ends of her wires around one another rather
        // than welding them, so every meeting is a small thickening that the
        // light catches.
        noStroke()
        for (n, point) in flat.enumerated() {
            guard let point else { continue }
            let t = clamp(map(depth[n], near, far, 0, 1), 0, 1)
            fill(wire.withAlpha(lerp(0.9, 0.2, t)))
            drawCircle(center: point, radius: lerp(1.9, 0.7, t))
        }
    }
}
