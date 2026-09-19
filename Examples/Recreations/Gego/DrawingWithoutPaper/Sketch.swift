//  Recreation after Gego (Gertrud Goldschmidt) - the Dibujos sin papel, made
//  from about 1976 to 1988: wire and scraps of metal bent and bound into small
//  works that hang a short way off the wall, so that lighting them throws a
//  shadow onto the wall and the shadow is the drawing.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.guggenheim-bilbao.eus/en/exhibition/dibujos-sin-papel-ca-1976-88
//
//  An original Ollin interpretation, written from the works and from the
//  accounts of how they were made. Nothing was ported: the pieces were bent,
//  woven and bound by hand from wire and from whatever was lying in the studio.

import Ollin

/// A drawing without paper (Gego, about 1976 to 1988). A lattice of wire bent
/// by hand, hanging a few centimeters off the wall, and a lamp that crosses it.
/// The piece is the small dark thing; the drawing is the shadow.
///
/// Gego called these drawings rather than sculptures, and meant it. The wire
/// stands in for the drawn line and the wall stands in for the paper, which
/// leaves the work with nothing of its own to be seen against: it needs the
/// wall, the lamp and the gap between them to become an image at all. Move the
/// lamp and the drawing is another drawing, made of the same wire.
///
/// So this sketch is built around that gap. Every point of the lattice carries
/// a `depth`, how far off the wall its bit of wire hangs, and the wall is the
/// canvas seen straight on, so the wire is drawn where it is. Its shadow is
/// where the ray from the lamp through that point meets the wall, which works
/// out at `lamp + (p - lamp) * lamp.z / (lamp.z - p.z)`: one projection from
/// one point, the same arithmetic the lamp does. The far corner of the frame
/// hangs further out than the wires behind it, so its shadow is thrown further
/// than theirs and the shadow is never a copy of the piece, only its relative.
///
/// The lattice is a grid that has stopped being one. The nodes are pushed off
/// true, so nothing is square; wires run past the frame and stop where they
/// stop; some of the grid is simply not there. Wires arrive one at a time at
/// `pace` a second until the piece is made, and then it hangs while the lamp
/// goes on crossing it, so the same wire draws a wide loose shadow at one
/// moment and a tight one at another. The air in the room moves the piece a
/// millimeter or two, which the shadow magnifies into something you can see:
/// that difference between what the wire does and what the shadow does is the
/// whole of it.
@main
final class DrawingWithoutPaper: Sketch {
    /// How many wires go in a second while the piece is being made.
    @Param(0.4 ... 12, icon: "timer") var pace = 1.6
    /// How far the lamp stands off the wall, in centimeters. Closer throws the
    /// shadow further out and pulls it about more as the lamp crosses.
    @Param(70 ... 600, icon: "lightbulb") var lampDistance = 150.0
    /// How long the lamp takes to cross the wall and come back, in seconds.
    @Param(6 ... 90, icon: "arrow.left.and.right") var sweep = 26.0
    /// How much the air moves the piece, in millimeters.
    @Param(0 ... 8, icon: "wind") var air = 2.4

    let wall = Color(hex: 0xE8E4DA)
    let wireInk = Color(hex: 0x24232A)
    let shadowInk = Color(hex: 0x6E6A66)

    /// One bent wire: a run of points on the wall's plane, each with the
    /// distance it hangs off the wall, plus how thick that wire is.
    struct Wire {
        var points: [Vector2]
        var depths: [Double]
        var width: Double
        var closed: Bool
    }

    var wires: [Wire] = []
    /// Where wires are bound to one another, and how far off the wall.
    var bindings: [(at: Vector2, depth: Double)] = []

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        bendTheWire()
    }

    // MARK: - The piece

    /// The lattice, bent and bound. A frame that is nearly a rectangle, a grid
    /// inside it that has been pushed off true, a few runs that carry on past
    /// the frame, and the parts that were left out.
    func bendTheWire() {
        randomSeed(7)
        let frame = Rectangle(center: Vector2(505, 545), width: 470, height: 610)
        let cols = 7, rows = 9
        wires = []
        bindings = []

        // Where each crossing of the grid sits, and how far it hangs off the
        // wall. Nothing here is on a line: the hand that bent it was working
        // against the wire, not with a rule.
        var node: [[Vector2]] = []
        var lift: [[Double]] = []
        for r in 0 ... rows {
            var rowPoints: [Vector2] = []
            var rowLift: [Double] = []
            for c in 0 ... cols {
                let u = Double(c) / Double(cols), v = Double(r) / Double(rows)
                let at = frame.point(u: u, v: v)
                let wobble = Vector2(signedNoise(u * 4.3, v * 4.3 + 40) * 24,
                                     signedNoise(u * 4.3 + 80, v * 4.3) * 21)
                rowPoints.append(at + wobble)
                // Off the wall between two and ten centimeters, deeper toward
                // one corner, so the shadow of one end of a wire is thrown
                // further than the shadow of the other.
                rowLift.append(2.0 + 8.0 * pow(noise(u * 1.7 + 5, v * 1.7 - 3), 1.3))
            }
            node.append(rowPoints)
            lift.append(rowLift)
        }

        // The frame, bent like everything else, and standing off the wall
        // further than anything it holds: it is what the piece is carried by,
        // and the weave is behind it. That shows in the shadow, where the
        // frame is thrown further than any wire inside it.
        let corner = [frame.topLeft, frame.topRight, frame.bottomRight, frame.bottomLeft]
        var framePoints: [Vector2] = []
        var frameDepths: [Double] = []
        for k in 0 ..< 4 {
            let a = corner[k], b = corner[(k + 1) % 4]
            for s in 0 ..< 3 {
                let t = Double(s) / 3
                let point = a.lerp(to: b, t)
                let off = Vector2(signedNoise(point.x * 0.012, point.y * 0.012 + 3) * 9,
                                  signedNoise(point.x * 0.012 + 9, point.y * 0.012) * 9)
                framePoints.append(point + off)
                frameDepths.append(12.6 + signedNoise(point.x * 0.01, point.y * 0.01 + 60) * 1.1)
            }
        }
        wires.append(Wire(points: framePoints, depths: frameDepths, width: 3.0, closed: true))

        // Which crossings a run actually reaches, so that the bindings can be
        // put only where two wires really meet.
        var onRow = Set<Int>(), onColumn = Set<Int>()

        // The rows. A run starts and ends where it likes, and some of them are
        // not there at all.
        for r in 0 ... rows {
            if random() < 0.16 { continue }
            let from = random() < 0.3 ? Int(random(1, 3)) : 0
            let to = random() < 0.3 ? cols - Int(random(1, 3)) : cols
            guard to - from >= 2 else { continue }
            var points = Array(node[r][from ... to])
            var depths = Array(lift[r][from ... to])
            for c in from ... to { onRow.insert(r * (cols + 1) + c) }
            // A run that carries on past the frame and stops in the air, which
            // is what keeps the piece from closing itself off.
            if from == 0, random() < 0.34 {
                let out = points[0] + (points[0] - points[1]).normalized * random(24, 62)
                points.insert(out, at: 0)
                depths.insert(depths[0] + random(-1.5, 2.5), at: 0)
            }
            wires.append(Wire(points: points, depths: depths,
                              width: random() < 0.25 ? 2.4 : 1.5, closed: false))
        }

        // The columns, the same way.
        for c in 0 ... cols {
            if random() < 0.2 { continue }
            let from = random() < 0.3 ? Int(random(1, 4)) : 0
            let to = random() < 0.3 ? rows - Int(random(1, 4)) : rows
            guard to - from >= 2 else { continue }
            var points = (from ... to).map { node[$0][c] }
            var depths = (from ... to).map { lift[$0][c] }
            for r in from ... to { onColumn.insert(r * (cols + 1) + c) }
            if to == rows, random() < 0.34 {
                let last = points.count - 1
                let out = points[last] + (points[last] - points[last - 1]).normalized * random(24, 70)
                points.append(out)
                depths.append(depths[last] + random(-1.5, 2.5))
            }
            wires.append(Wire(points: points, depths: depths,
                              width: random() < 0.25 ? 2.4 : 1.5, closed: false))
        }

        // Where two wires cross they are bound: a turn of thread, a scrap of
        // tube, whatever was to hand. A binding needs two wires, so only the
        // crossings that a run and a column both reach are bound, and the
        // bindings end up mapping what is actually there.
        for r in 0 ... rows {
            for c in 0 ... cols {
                let key = r * (cols + 1) + c
                guard onRow.contains(key), onColumn.contains(key) else { continue }
                if random() < 0.72 { bindings.append((node[r][c], lift[r][c])) }
            }
        }
    }

    // MARK: - The lamp

    /// Where the lamp hangs this frame. It crosses the wall and comes back,
    /// which is all the event this piece needs.
    var lamp: Vector3 {
        let t = time / max(sweep, 0.001) * .pi * 2
        return Vector3(540 + sin(t) * 430, 190 + cos(t * 0.5) * 90, lampDistance)
    }

    /// Where the wall takes the shadow of a point hanging `depth` off it.
    /// One lamp, one projection: the ray from the lamp through the point,
    /// carried on until it lands.
    func shadow(of point: Vector2, depth: Double, lamp: Vector3) -> Vector2 {
        let t = lamp.z / max(lamp.z - depth, 0.001)
        return Vector2(lamp.x, lamp.y) + (point - Vector2(lamp.x, lamp.y)) * t
    }

    // MARK: - Drawing

    override func draw() {
        background(wall)
        let lamp = self.lamp
        let made = min(wires.count, 1 + Int(time * pace))

        // The air in the room. The piece moves by a millimeter or two and the
        // shadow moves by rather more, which is the thing to watch.
        let breath = Vector2(signedNoise(time * 0.23) , signedNoise(time * 0.19 + 12)) * air

        washTheWall(lamp: lamp)

        // The shadows first: the wall is behind the piece, so its drawing is
        // laid down before the wire that casts it.
        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for wire in wires.prefix(made) {
            let cast = zip(wire.points, wire.depths).map {
                shadow(of: $0 + breath, depth: $1, lamp: lamp)
            }
            stroke(shadowInk.withAlpha(0.14))
            strokeWeight(wire.width * 4.2)
            drawPolyline(cast, closed: wire.closed)
            stroke(shadowInk.withAlpha(0.4))
            strokeWeight(wire.width * 1.8)
            drawPolyline(cast, closed: wire.closed)
        }
        for binding in bindings.prefix(bindingsShown(made: made)) {
            let cast = shadow(of: binding.at + breath, depth: binding.depth, lamp: lamp)
            noStroke()
            fill(shadowInk.withAlpha(0.34))
            drawCircle(center: cast, radius: 6.5)
            noFill()
        }

        // Then the wire itself, seen straight on, where it hangs.
        for wire in wires.prefix(made) {
            stroke(wireInk)
            strokeWeight(wire.width)
            drawPolyline(wire.points.map { $0 + breath }, closed: wire.closed)
        }
        noStroke()
        for binding in bindings.prefix(bindingsShown(made: made)) {
            fill(wireInk)
            drawCircle(center: binding.at + breath, radius: 3.4)
        }

        drawText("the piece is the wire, the drawing is its shadow", width / 2,
                 height - 44, size: 15, color: wireInk.withAlpha(0.45),
                 align: .center, .bottom)
    }

    /// The bindings go in as the wires they hold do.
    func bindingsShown(made: Int) -> Int {
        guard wires.count > 1 else { return 0 }
        let done = Double(made - 1) / Double(wires.count - 1)
        return Int(Double(bindings.count) * clamp(done, 0, 1))
    }

    /// The light the lamp lays on the wall. A wall under a lamp is not one
    /// flat tone, and the drawing sits in whatever the lamp leaves.
    func washTheWall(lamp: Vector3) {
        let foot = Vector2(lamp.x, lamp.y)
        noStroke()
        for ring in stride(from: 900.0, to: 120.0, by: -70.0) {
            fill(Color.white.withAlpha(0.035))
            drawCircle(center: foot, radius: ring)
        }
    }
}
