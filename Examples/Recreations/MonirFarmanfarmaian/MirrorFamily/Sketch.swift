//  Recreation after Monir Shahroudy Farmanfarmaian - the Families (2010 to
//  2016), wall reliefs of cut mirror, reverse-painted glass, and plaster on
//  wood, each family running from the triangle to the decagon; the facets
//  after Untitled Heptagon 11 (2016).
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.guggenheim.org/exhibition/monir
//
//  An original Ollin interpretation, written from the works and from her own
//  account of the geometry. Nothing was ported: the works were cut and set by
//  hand, in plaster on wood, by craftsmen in her Tehran studio.

import Ollin

/// The Families (Monir Shahroudy Farmanfarmaian, 2010 to 2016). Farmanfarmaian
/// grouped her mirror reliefs into families, and each family begins with the
/// triangle and ends with the decagon. The geometry is hers, in her words: all
/// these polygons can be inscribed in a circle, and dividing the circle into
/// three equal arcs and joining the points gives a triangle, into four a
/// square, and so on. Every member here is cut from the circle that way, and
/// the sketch sets one member after another, triangle to decagon and around
/// again.
///
/// Inside the outline the polygon is cut again. Lines from the center to the
/// corners split it into one triangle for every side, and `rings` nested
/// copies of the outline cut each of those into rows of small triangles,
/// `rings * rings` to a side. Every small triangle is one piece of mirror set
/// in plaster, with a thin line of plaster showing around it. Every third
/// point of that lattice is pressed up out of the plaster, so every piece
/// tilts, and the six pieces around a raised point make a small six-sided
/// star: the hexagon she said every mosque in Iran is built on. (Where two
/// sides' lattices meet along a spoke they agree only on every third ring, so
/// a spoke is pressed up only there.)
///
/// Some of those stars are cut from glass painted on the back instead of from
/// mirror: the one at the center, the ones on the spokes out to two thirds of
/// the way, and one halfway along each side of the middle ring. Together they
/// draw a star with as many points as the polygon has sides, and the paint
/// changes color from one member to the next.
///
/// The pieces go in from the center out, ring by ring, at `pace` pieces a
/// second, and the finished relief hangs for `hold` seconds while a lamp moves
/// in front of it. A mirror shows only what faces it, so every piece shows a
/// different part of the room: the pale ceiling and its lamps, the dark
/// floor, the doorway. The reflections are traced against the real room, so
/// they change as the lamp and the viewer move. `firstSides` is the member the
/// run starts on, and a press moves on to the next.
///
/// `--export-usdz relief.usda --frame 600` writes the frame's meshes out as
/// text, the mirror and the painted glass each as one mesh with a triangle per
/// piece. The relief can be read back from that file: `sides * rings * rings`
/// pieces, a turn of one side's angle that maps every piece onto a piece of
/// the same kind at the same height, and a mirror line through the top.
@main
final class MirrorFamily: Sketch {
    @Param(3 ... 10, icon: "hexagon") var firstSides = 7
    @Param(6 ... 15, icon: "circle.circle") var rings = 9
    @Param(10 ... 400, icon: "square.stack.3d.up") var pace = 90.0
    @Param(0 ... 30, icon: "clock") var hold = 8.0

    private let wall = Color(hex: 0xE9E4DA)
    private let plaster = Color(hex: 0xF3EFE6)
    private let backing = Color(hex: 0x141414)
    private let silver = Color(hex: 0xF4F5F6)
    private let floorColor = Color(hex: 0x333436)
    private let shade = Color(hex: 0x7D7870)

    /// The paint behind the glass, taken in turn from one member to the next,
    /// in the reds, greens, and blues her reliefs carry.
    private let paints: [Color] = [
        Color(hex: 0xB8322A), Color(hex: 0x2E7D4F), Color(hex: 0x2A4FA8),
    ]

    /// A lamp, flat white so it reads the same in the room and in a mirror.
    private let glow = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E6))

    /// One piece: a triangle of mirror or of painted glass.
    private struct Piece {
        var corners: [Vector3]
        var isGlass: Bool
    }

    /// One member of the family: its outline, and every piece cut for it in
    /// the order the pieces are set.
    private struct Member {
        var outline: [Vector2]
        var pieces: [Piece]
    }

    private var member: Member?
    private var began = 0.0
    private var index = 0
    private var program = (first: 0, rings: 0)

    override func mousePressed() {
        index += 1
        member = nil
    }

    override func draw() {
        let wanted = (first: firstSides, rings: rings)
        if program != wanted {
            program = wanted
            index = 0
            member = nil
        }
        let sides = 3 + (firstSides - 3 + index) % 8
        if member == nil {
            member = Self.cut(sides: sides, rings: rings, radius: 1.6)
            began = time
        }
        guard let member else { return }

        let elapsed = time - began
        let setting = Double(member.pieces.count) / pace
        if elapsed > setting + hold + 0.6 {
            index += 1
            self.member = nil
        }

        background(wall)
        let drift = time * 0.19
        camera(.perspective(eye: Vector3(sin(drift) * 1.3, 0.25 + sin(time * 0.13) * 0.3, 7.6),
                            target: Vector3(0, 0, 0.15), fieldOfView: 0.55, near: 0.5, far: 30))
        environment(.studio.intensified(to: 0.35))
        toneMap(.aces)
        temporalAntialiasing()
        rayTracedReflections()
        reflectionBounces(2)

        // The lamp moves in front of the relief, above the frame, so the
        // mirrors catch it.
        let lamp = Vector3(cos(time * 0.31) * 2.6, 2.3 + sin(time * 0.23) * 0.5, 3.2)
        pointLight(Color(hue: 0.1, saturation: 0.2, brightness: 1), at: lamp, intensity: 9)
        ambientLight(Color(white: 0.08))
        withState {
            translate(lamp.x, lamp.y, lamp.z)
            fill(.white)
            matcap(glow)
            drawSphere(radius: 0.14)
        }

        // The room the mirrors show: a dark floor, a pale ceiling hung with
        // a row of lamps, and a doorway in the wall behind the viewer.
        let room: [(size: Vector3, at: Vector3, color: Color)] = [
            (Vector3(14, 10, 0.1), Vector3(0, 1, -0.05), wall),
            (Vector3(14, 0.1, 14), Vector3(0, -3.2, 6), floorColor),
            (Vector3(14, 0.1, 14), Vector3(0, 5.2, 6), plaster),
            (Vector3(14, 10, 0.1), Vector3(0, 1, 12.5), shade),
            (Vector3(2.4, 5.6, 0.1), Vector3(0.6, -0.4, 12.4), backing),
            (Vector3(0.1, 10, 14), Vector3(-6.5, 1, 6), shade),
            (Vector3(0.1, 10, 14), Vector3(6.5, 1, 6), shade),
        ]
        for part in room {
            withState {
                fill(part.color)
                material(.matte)
                translate(part.at.x, part.at.y, part.at.z)
                drawBox(width: part.size.x, height: part.size.y, depth: part.size.z)
            }
        }
        // An arc of lamps hung in front of the relief, above the viewer, where
        // the pieces that tilt up can see them.
        for i in 0 ..< 7 {
            let a = (Double(i) - 3) / 3
            withState {
                translate(a * 3.2, 3.1 - a * a * 0.5 + sin(time * 0.6 + Double(i)) * 0.05,
                          5.2 + a * a * 0.8)
                fill(.white)
                matcap(glow)
                drawSphere(radius: 0.14)
            }
        }
        // The relief stands off the wall, so the lamp throws its outline
        // onto the wall behind it, softly.
        let throwAway = Vector2(-lamp.x, -lamp.y) * (0.3 / (lamp.z - 0.3))
        for layer in 0 ..< 5 {
            withState {
                fill(Color(white: 0.05, alpha: 0.13))
                material(.matte)
                translate(throwAway.x, throwAway.y, 0.004 + Double(layer) * 0.002)
                let grow = 1.05 - Double(layer) * 0.02
                drawExtrude(member.outline.map { $0 * grow }, depth: 0.002)
            }
        }
        withState {
            fill(backing)
            material(.matte)
            translate(0, 0, 0.07)
            drawExtrude(member.outline, depth: 0.14)
        }
        withState {
            fill(plaster)
            material(.matte)
            translate(0, 0, 0.145)
            drawExtrude(member.outline.map { $0 * 0.985 }, depth: 0.01)
        }

        // The pieces set so far, each dropping into its bed.
        let placed = min(member.pieces.count, Int(elapsed * pace))
        var mirror = MeshCut(), glass = MeshCut()
        for i in 0 ..< placed {
            let piece = member.pieces[i]
            let age = elapsed - Double(i) / pace
            let lift = 0.35 * pow(max(0, 1 - age / 0.35), 2)
            if piece.isGlass {
                // Paint laid on by hand is never one even coat.
                glass.add(piece.corners, lift: lift, shade: 0.8 + 0.2 * noise(Double(i) * 0.61))
            } else {
                mirror.add(piece.corners, lift: lift)
            }
        }
        if let mesh = mirror.mesh {
            withState {
                fill(silver)
                material(.metal(roughness: 0.1))
                drawMesh(mesh)
            }
        }
        if let mesh = glass.mesh {
            withState {
                fill(paints[index % paints.count])
                var painted = Material.dielectric(roughness: 0.55)
                painted.clearcoat = 1
                painted.clearcoatRoughness = 0.03
                material(painted)
                drawMesh(mesh)
            }
        }
    }

    /// Triangles gathered into one flat-shaded mesh.
    private struct MeshCut {
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var colors: [Color] = []

        mutating func add(_ corners: [Vector3], lift: Double, shade: Double = 1) {
            let a = corners[0], b = corners[1], c = corners[2]
            let normal = (b - a).cross(c - a).normalized
            for p in [a, b, c] {
                positions.append(p + Vector3(0, 0, lift))
                normals.append(normal)
                colors.append(Color(white: shade))
            }
        }

        var mesh: Mesh? {
            positions.isEmpty ? nil
                : Mesh(positions: positions, normals: normals,
                       indices: (0 ..< UInt32(positions.count)).map { $0 }, colors: colors)
        }
    }

    /// Cuts one member: the circle divided into `sides` arcs for the outline,
    /// every side's sector cut into a lattice of `rings * rings` triangles.
    private nonisolated static func cut(sides n: Int, rings: Int, radius: Double) -> Member {
        let sector = 2 * Double.pi / Double(n)
        // An odd polygon stands on a corner-up axis, an even one hangs flat
        // along its top edge.
        let top = Double.pi / 2 + (n % 2 == 0 ? sector / 2 : 0)
        let corners = (0 ... n).map { i -> Vector2 in
            let a = top + Double(i) * sector
            return Vector2(cos(a), sin(a)) * radius
        }
        let base = 0.15, dome = 0.12, peak = 0.05
        /// The point `p` steps along ring `k` of sector `i`: ring `k` is the
        /// outline scaled to `k / rings`, and its side is cut into `k` steps.
        func point(_ i: Int, _ k: Int, _ p: Int) -> Vector3 {
            let flat = k == 0 ? Vector2.zero
                : (corners[i] + (corners[i + 1] - corners[i]) * (Double(p) / Double(k)))
                    * (Double(k) / Double(rings))
            var z = base + dome * (1 - Double(k) / Double(rings))
            if isRaised(k, p) { z += peak }
            return Vector3(flat.x, flat.y, z)
        }
        func isRaised(_ k: Int, _ p: Int) -> Bool {
            guard k < rings else { return false }
            // On a spoke the two sectors' rules agree only every third ring.
            if p == 0 || p == k { return k % 3 == 0 }
            return (k + p) % 3 == 0
        }
        func isGlass(_ k: Int, _ p: Int) -> Bool {
            guard isRaised(k, p) else { return false }
            // The star at the center, the raised stars on the spokes out to
            // two thirds of the way, in line with the corners, and the stars
            // halfway along the middle ring, in line with the sides.
            if p == 0 || p == k { return k <= 2 * rings / 3 }
            return k == 2 * (rings / 4) && 2 * p == k
        }

        var pieces: [Piece] = []
        for k in 1 ... rings {
            for i in 0 ..< n {
                for p in 0 ..< k {
                    // Pointing out: two corners on this ring, one inside.
                    var cells = [[(k, p), (k, p + 1), (k - 1, p)]]
                    // Pointing in: two corners inside, one on this ring.
                    if p < k - 1 { cells.append([(k - 1, p), (k, p + 1), (k - 1, p + 1)]) }
                    for cell in cells {
                        let flat = cell.map { point(i, $0.0, $0.1) }
                        // A piece belongs to the raised point among its corners.
                        let glass = cell.contains { isGlass($0.0, $0.1) }
                        pieces.append(Piece(corners: inset(flat, by: 0.0045), isGlass: glass))
                    }
                }
            }
        }
        return Member(outline: Array(corners.dropLast()), pieces: pieces)
    }

    /// Shrinks a triangle about its incenter so a line of plaster shows
    /// the same width around every piece.
    private nonisolated static func inset(_ c: [Vector3], by gap: Double) -> [Vector3] {
        let la = (c[1] - c[2]).length, lb = (c[2] - c[0]).length, lc = (c[0] - c[1]).length
        let perimeter = la + lb + lc
        let center = (c[0] * la + c[1] * lb + c[2] * lc) / perimeter
        let area = (c[1] - c[0]).cross(c[2] - c[0]).length / 2
        let inradius = 2 * area / perimeter
        let s = max(0, (inradius - gap) / inradius)
        var out = c.map { center + ($0 - center) * s }
        // Face the viewer.
        if (out[1] - out[0]).cross(out[2] - out[0]).z < 0 { out.swapAt(1, 2) }
        return out
    }
}
