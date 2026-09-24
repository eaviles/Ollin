//  Recreation after Monir Shahroudy Farmanfarmaian - the felt-tip drawings on
//  the grid of triangles, read from Geometric (2014, felt-tip pen and
//  metallic pen on paper, 70.5 x 100 cm) and Geometric (2013, felt-tip pen
//  and glitter on paper, 61 x 92.3 cm), both shown by James Cohan in
//  Mirror-works and Drawings (2004-2016), 2021, and from On Hexagon (2012,
//  felt marker, color pencil and mirror on paper).
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.jamescohan.com/exhibitions/monir-shahroudy-farmanfarmaian2
//
//  An original Ollin interpretation, written from the drawings. Nothing was
//  ported: the drawings are felt-tip pen on paper, ruled by hand.

import Ollin

/// After the Geometric drawings (Monir Shahroudy Farmanfarmaian, 2013 and
/// 2014). "Everything starts with the hexagon," she said, and in the drawings
/// of her last decade it starts on paper. A sheet is ruled all over with a
/// grid of equal triangles in fine black pen, and sparser lines in red, green,
/// and orange cross it through the same points at the angles in between. At
/// the middle a hexagon sits on the grid with smaller hexagons inside it, and
/// every ring between two of them is hatched with lines that run parallel to
/// its sides, packed closer toward the middle, so the hexagon reads as a
/// tunnel going back into the sheet. Outside it, some of the grid's triangles
/// are filled with short strokes of felt-tip in two colors, most of them in
/// pairs that meet at a point like a bow tie, and a few carry a green zigzag
/// instead.
///
/// The sketch rules one sheet at a time, in the order a hand would: the black
/// grid one direction after another, the colored lines, the hexagons, the
/// hatching from the outer ring in, and the spokes over it, then the filled
/// triangles pair by pair. Then it holds the sheet for `hold` seconds and
/// starts the next one. `cell` is the side of one triangle of the grid,
/// `rings` how many hexagons are nested, `hatch` how many hatching lines cross
/// the outer ring (each ring inward takes that many more), `ties` how many
/// pairs of triangles are dealt, and `pace` how fast the hand works. The seed
/// is the sheet; a press starts the next one.
///
/// Every mark is a stroke and every stroke is a line, so `--export-svg` is a
/// plotter drawing and the grid can be read back from it. Every corner of the
/// grid, the colored lines, the hexagons, and the spokes is a point of the
/// grid. Every corner of the hatching and the zigzags is a point of the same
/// grid cut finer, into as many parts as the least common multiple of the
/// rings' hatching counts and the zigzag's six. The filled triangles are the
/// grid's own, all outside the hexagon, and the set of them is the same seen
/// in a mirror left to right or top to bottom.
@main
final class Geometric: Sketch {
    @Param(60 ... 110, icon: "triangle") var cell = 80.0
    @Param(2 ... 4, icon: "hexagon") var rings = 3
    @Param(3 ... 9, icon: "line.3.horizontal") var hatch = 6
    @Param(4 ... 24, icon: "square.grid.3x3") var ties = 12
    @Param(0.25 ... 6, icon: "pencil.tip") var pace = 1.0
    @Param(0 ... 30, icon: "clock") var hold = 8.0

    override var canvasSize: CanvasSize { .size(1400, 1000) }

    /// The paper's margin: every point of the grid sits inside it.
    private let margin = 70.0
    /// How many segments a zigzag runs from the pair's shared point to the far
    /// side of its triangle.
    private nonisolated static let zigzag = 6

    private let paper = Color(hex: 0xF3EFE6)
    /// The pens: black, then the colored lines, then the felt-tip colors.
    private nonisolated static let black = 0, red = 1, green = 2, orange = 3, ochre = 4
    private let pens: [Color] = [
        Color(hex: 0x1D1B1A), Color(hex: 0xC8372D), Color(hex: 0x3B8A3E),
        Color(hex: 0xE38A2B), Color(hex: 0xC49A3A),
    ]

    /// The weights, one to a kind of mark, so the drawing can be sorted back
    /// out of its export by weight alone.
    private enum Weight {
        static let grid = 1.1, colored = 0.9, outline = 3.2, spoke = 2.6
        static let hatching = 0.7, twin = 0.8, zigzag = 2.0, dab = 2.3
    }

    /// One stroke of the pen, as the points it passes through.
    private struct Mark {
        var points: [Vector2]
        var closed: Bool
        var pen: Int
        var weight: Double
        /// How long the hand takes over it at `pace` 1, in seconds.
        var seconds: Double

        var length: Double {
            var total = 0.0
            let path = closed ? points + [points[0]] : points
            for k in 1 ..< path.count { total += (path[k] - path[k - 1]).length }
            return total
        }
    }

    private struct Sheet {
        var marks: [Mark]
        /// When each mark is finished, at `pace` 1.
        var ends: [Double]
    }

    private var sheet: Sheet?
    private var began = 0.0
    private var index = 0
    private var program: [Double] = []

    override func mousePressed() {
        index += 1
        sheet = nil
    }

    override func draw() {
        let wanted = [cell, Double(rings), Double(hatch), Double(ties)]
        if wanted != program {
            program = wanted
            sheet = nil
        }
        if sheet == nil {
            randomSeed(variation &+ index)
            sheet = rule()
            began = time
        }
        guard let sheet, let total = sheet.ends.last else { return }
        let clock = (time - began) * pace
        if clock > total + hold * pace {
            index += 1
            self.sheet = nil
        }

        background(paper)
        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for (k, mark) in sheet.marks.enumerated() {
            let start = k == 0 ? 0 : sheet.ends[k - 1]
            if clock <= start { break }
            stroke(pens[mark.pen])
            strokeWeight(mark.weight)
            if clock >= sheet.ends[k] {
                if mark.points.count == 2 {
                    drawLine(mark.points[0], mark.points[1])
                } else {
                    drawPolyline(mark.points, closed: mark.closed)
                }
            } else {
                // The pen is partway along this one.
                drawPolyline(Self.along(mark, fraction: (clock - start) / mark.seconds))
            }
        }
    }

    /// The first `fraction` of a mark, by length.
    private nonisolated static func along(_ mark: Mark, fraction: Double) -> [Vector2] {
        let path = mark.closed ? mark.points + [mark.points[0]] : mark.points
        var left = mark.length * max(0, min(1, fraction))
        var out = [path[0]]
        for k in 1 ..< path.count {
            let step = (path[k] - path[k - 1]).length
            if left >= step {
                out.append(path[k])
                left -= step
            } else {
                out.append(path[k - 1] + (path[k] - path[k - 1]) * (left / step))
                break
            }
        }
        return out.count > 1 ? out : [path[0], path[0]]
    }

    // MARK: - Ruling one sheet

    /// A point of the grid, by its steps along the two sides of a triangle.
    private struct Node: Hashable {
        var i: Int, j: Int
        static func + (p: Node, q: Node) -> Node { Node(i: p.i + q.i, j: p.j + q.j) }
        static func - (p: Node, q: Node) -> Node { Node(i: p.i - q.i, j: p.j - q.j) }
        /// Steps from the middle, counted the way a hexagon of the grid grows:
        /// every node of the hexagon of radius `r` is `r` steps out.
        var rings: Int { (abs(i) + abs(j) + abs(i + j)) / 2 }
        /// Seen in a mirror standing upright through the middle.
        var leftToRight: Node { Node(i: -i - j, j: j) }
        /// Seen in a mirror lying level through the middle.
        var topToBottom: Node { Node(i: i + j, j: -j) }
    }

    /// Deals the whole sheet, every mark in the order the hand makes it.
    private func rule() -> Sheet {
        let s = cell
        let center = Vector2(width / 2, height / 2)
        // One side of a triangle runs level; the other climbs at sixty degrees.
        let a = Vector2(s, 0), b = Vector2(s / 2, -s * 3.0.squareRoot() / 2)
        func place(_ n: Node) -> Vector2 { center + a * Double(n.i) + b * Double(n.j) }
        func place(_ n: Node, scaledBy f: Double) -> Vector2 {
            center + (a * Double(n.i) + b * Double(n.j)) * f
        }
        let x0 = margin, x1 = width - margin, y0 = margin, y1 = height - margin
        func onSheet(_ n: Node) -> Bool {
            let p = place(n)
            return p.x >= x0 - 1e-9 && p.x <= x1 + 1e-9 && p.y >= y0 - 1e-9 && p.y <= y1 + 1e-9
        }
        let reachJ = Int(height / (s * 0.8)) + 2, reachI = Int(width / s) + reachJ + 2
        var nodes: [Node] = []
        for j in -reachJ ... reachJ {
            for i in -reachI ... reachI where onSheet(Node(i: i, j: j)) {
                nodes.append(Node(i: i, j: j))
            }
        }

        var marks: [Mark] = []
        let ruled = 5400.0, hatched = 6400.0, zigzagged = 1500.0, dabsPerSecond = 700.0
        func add(_ points: [Vector2], closed: Bool = false, pen: Int, weight: Double,
                 speed: Double) {
            var mark = Mark(points: points, closed: closed, pen: pen, weight: weight, seconds: 0)
            mark.seconds = max(0.01, mark.length / speed)
            marks.append(mark)
        }

        // 1. The lines through the grid in one direction, each from its first
        // node on the sheet to its last, alternately left to right and back.
        // `every` keeps only every so many lines, counted from the middle.
        func lines(along d: Node, every: Int, pen: Int, weight: Double) {
            var lines: [Int: [Node]] = [:]
            for n in nodes { lines[n.i * d.j - n.j * d.i, default: []].append(n) }
            let direction = place(d) - center
            var flip = false
            for key in lines.keys.sorted() where key % every == 0 {
                let run = lines[key]!.sorted { place($0).dot(direction) < place($1).dot(direction) }
                guard run.count > 1 else { continue }
                let ends = [place(run.first!), place(run.last!)]
                add(flip ? ends.reversed() : ends, pen: pen, weight: weight, speed: ruled)
                flip.toggle()
            }
        }
        for d in [Node(i: 1, j: 0), Node(i: 0, j: 1), Node(i: -1, j: 1)] {
            lines(along: d, every: 1, pen: Self.black, weight: Weight.grid)
        }
        // The colored lines run through the same nodes at the angles halfway
        // between, every third of them.
        for (d, pen) in [(Node(i: 1, j: 1), Self.red), (Node(i: -1, j: 2), Self.orange),
                         (Node(i: -2, j: 1), Self.green)] {
            lines(along: d, every: 3, pen: pen, weight: Weight.colored)
        }

        // 2. The hexagons, the hatching from the outer ring in, and the spokes.
        let corners = [Node(i: 1, j: 0), Node(i: 0, j: 1), Node(i: -1, j: 1),
                       Node(i: -1, j: 0), Node(i: 0, j: -1), Node(i: 1, j: -1)]
        func hexagon(_ r: Double) -> [Vector2] { corners.map { place($0, scaledBy: r) } }
        for r in stride(from: rings, through: 1, by: -1) {
            add(hexagon(Double(r)), closed: true, pen: Self.black, weight: Weight.outline,
                speed: ruled)
        }
        for r in stride(from: rings, through: 1, by: -1) {
            // Ring `r` runs from the hexagon of radius r - 1 out to r, cut into
            // `lines` equal steps: the outer ring into `hatch`, each ring in by
            // `hatch` more.
            let lines = hatch * (rings + 1 - r)
            for m in stride(from: lines - 1, through: 1, by: -1) {
                let radius = Double(r - 1) + Double(m) / Double(lines)
                // The two lines just inside each outline are drawn in color.
                let pen = m == lines - 1 ? Self.red : m == lines - 2 ? Self.green : Self.black
                add(hexagon(radius), closed: true, pen: pen,
                    weight: pen == Self.black ? Weight.hatching : Weight.twin, speed: hatched)
            }
        }
        for corner in corners {
            add([center, place(corner, scaledBy: Double(rings))], pen: Self.black,
                weight: Weight.spoke, speed: ruled)
        }

        // 3. The filled triangles, dealt as pairs meeting at a point and
        // mirrored both ways across the sheet.
        typealias Triangle = [Node]
        func key(_ t: Triangle) -> [Node] {
            t.sorted { ($0.i, $0.j) < ($1.i, $1.j) }
        }
        let onPaper = Set(nodes)
        func usable(_ t: Triangle) -> Bool {
            t.allSatisfy { onPaper.contains($0) && $0.rings >= rings }
        }
        // The three pairs at a node, each a triangle and its reflection
        // through the node, by the two sides that leave the node.
        let pairs: [[Node]] = [[Node(i: 1, j: 0), Node(i: 0, j: 1)],
                               [Node(i: 0, j: 1), Node(i: -1, j: 1)],
                               [Node(i: -1, j: 1), Node(i: -1, j: 0)]]
        let images: [(Node) -> Node] = [{ $0 }, { $0.leftToRight }, { $0.topToBottom },
                                        { $0.leftToRight.topToBottom }]
        // The hand goes round the sheet: the mirror images in reading order.
        func order(_ n: Node) -> Double {
            let p = place(n)
            return (p.y / s).rounded() * 10_000 + p.x
        }
        var used = Set<[Node]>()
        let felt = [Self.red, Self.green, Self.orange, Self.ochre]
        var dealt = 0, tries = 0
        while dealt < ties && tries < ties * 60 {
            tries += 1
            let at = nodes[Int(random(Double(nodes.count))) % nodes.count]
            let arms = pairs[Int(random(3)) % 3]
            let first: Triangle = [at, at + arms[0], at + arms[1]]
            let second: Triangle = [at, at - arms[0], at - arms[1]]
            // The pair and its three mirror images, each of them once.
            var orbit: [(Triangle, Node)] = []
            for (t, apex) in [(first, at), (second, at)] {
                for image in images {
                    let mirrored = t.map(image)
                    if !orbit.contains(where: { key($0.0) == key(mirrored) }) {
                        orbit.append((mirrored, image(apex)))
                    }
                }
            }
            guard orbit.allSatisfy({ usable($0.0) && !used.contains(key($0.0)) }) else { continue }
            dealt += 1
            let main = felt[Int(random(Double(felt.count))) % felt.count]
            var accent = felt[Int(random(Double(felt.count))) % felt.count]
            if accent == main { accent = felt[(felt.firstIndex(of: main)! + 1) % felt.count] }
            let zigzag = random(1) < 0.2
            for (t, apex) in orbit.sorted(by: { order($0.1) < order($1.1) }) {
                used.insert(key(t))
                let points = t.map { place($0) }
                if zigzag {
                    // From the shared point out to the far side, touching the
                    // two sides in turn at sixths of their length.
                    let tip = place(apex), rest = points.filter { $0 != tip }
                    var path = [tip]
                    for m in 1 ... Self.zigzag {
                        let side = m % 2 == 1 ? rest[0] : rest[1]
                        path.append(tip + (side - tip) * (Double(m) / Double(Self.zigzag)))
                    }
                    add(path, pen: Self.green, weight: Weight.zigzag, speed: zigzagged)
                } else {
                    for dab in dabs(in: points) {
                        marks.append(Mark(points: dab, closed: false,
                                          pen: random(1) < 0.75 ? main : accent,
                                          weight: Weight.dab, seconds: 1 / dabsPerSecond))
                    }
                }
            }
        }
        var ends: [Double] = []
        var clock = 0.0
        for mark in marks {
            clock += mark.seconds
            ends.append(clock)
        }
        return Sheet(marks: marks, ends: ends)
    }

    /// Short strokes of felt-tip scattered over a triangle, each whole inside
    /// it, clear of its sides by the pen's width.
    private func dabs(in t: [Vector2]) -> [[Vector2]] {
        let area = abs((t[1] - t[0]).cross(t[2] - t[0])) / 2
        let count = Int(area / 28)
        let lean = random(0, .pi)
        let clear = Weight.dab / 2 + 1.2
        func inside(_ p: Vector2) -> Bool {
            for k in 0 ..< 3 {
                let u = t[k], v = t[(k + 1) % 3], w = t[(k + 2) % 3]
                let edge = (v - u).normalized
                let side = (p - u).cross(edge), far = (w - u).cross(edge)
                // On the same side as the third corner, and far enough in.
                if side * far <= 0 || abs(side) < clear { return false }
            }
            return true
        }
        var out: [[Vector2]] = []
        var tries = 0
        while out.count < count && tries < count * 30 {
            tries += 1
            var u = random(1), v = random(1)
            if u + v > 1 { (u, v) = (1 - u, 1 - v) }
            let middle = t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v
            let angle = lean + random(-0.5, 0.5)
            let half = Vector2(cos(angle), sin(angle)) * (random(4.5, 8) / 2)
            let dab = [middle - half, middle + half]
            if inside(dab[0]) && inside(dab[1]) { out.append(dab) }
        }
        return out
    }
}
