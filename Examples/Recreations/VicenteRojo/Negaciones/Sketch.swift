//  Recreation after Vicente Rojo - the "Negaciones" series (1971-1974), the
//  square paintings built on the letter T, each one meant to deny the one
//  before it. A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist or his estate.
//  https://www.museoreinasofia.es/colecciones/obra/negacion-13/
//
//  An original Ollin interpretation written from the paintings and from what
//  Rojo said about them. Nothing was ported: the series is acrylic on canvas.

import Ollin

/// "Negaciones" (Vicente Rojo, 1971-1974). In 1970 Rojo took the letter T as
/// the whole structure of his painting, and for four years painted it again
/// and again on a strictly square canvas. He named the series for what he
/// wanted from it: paintings that would deny each other, and deny him as
/// their author. He thought of showing them as the work of forty invented
/// painters, and gave that up only because he could not think of forty names.
/// What he kept was the method: "starting from a very rigid structure, within
/// a strictly square form, which paradoxically allowed me to work with great
/// freedom."
///
/// The negation, in the paintings themselves, is this: the T is not painted.
/// What is painted is the shadow it would cast. A T-shaped block stands off
/// the canvas, light falls on it from one corner, and the sides of the block
/// are what you see, stepped in a few flat tones from the letter outward,
/// with a forty-five degree cut wherever a side ends. The face of the block
/// is the same color as the ground, so the letter is there only by what it
/// hides.
///
/// This sketch hangs a wall of them and keeps painting. Each panel is one
/// negation: which way the letter stands, which corner the light comes from,
/// which sides of the block are painted and which are left out, the
/// proportions of the letter, and the tones. Every `pace` seconds one panel
/// is painted over with a negation that matches no panel on the wall, so the
/// wall never settles and no painting is the last one. `stripes` is how many
/// tones the shadow steps through, `depth` how far the block stands off the
/// canvas, `across` how many panels a side, and `variation` the whole wall.
/// A press paints the next panel now.
///
/// Every shadow exports as flat polygons and the letter as one path in the
/// ground's own color, so `--export-svg` gives the wall back the way it was
/// painted: the T is in the file, and invisible.
@main
final class Negaciones: Sketch {
    @Param(2 ... 5, icon: "square.grid.3x3") var across = 3
    @Param(2 ... 5, icon: "square.3.layers.3d") var stripes = 3
    @Param(0.06 ... 0.24, icon: "sun.max") var depth = 0.13
    @Param(1 ... 20, icon: "clock") var pace = 3.0

    /// How long painting one panel over takes: the ground rolls down first,
    /// then the tones are laid from the deepest one to the one against the
    /// letter.
    private let brush = 1.2

    /// The wall the panels hang on.
    private let wall = Color(hex: 0xE8E3D8)

    /// The tones a negation chooses from: a ground, the stripe against the
    /// letter, and the stripe farthest from it, with the rest mixed between.
    /// The first family is the one on the painting in the header.
    private static let families: [(ground: Color, near: Color, far: Color)] = [
        (Color(hex: 0x8F8C6C), Color(hex: 0xEAC84D), Color(hex: 0x998C38)),
        (Color(hex: 0x9CA2A7), Color(hex: 0xE6EAEC), Color(hex: 0x6C7782)),
        (Color(hex: 0xAE9884), Color(hex: 0xEBC3AE), Color(hex: 0x76574A)),
        (Color(hex: 0xC0A16B), Color(hex: 0xD9573C), Color(hex: 0x7C392A)),
        (Color(hex: 0x7B8B73), Color(hex: 0xCFD895), Color(hex: 0x586845)),
        (Color(hex: 0x4B5163), Color(hex: 0xB8C1D6), Color(hex: 0x2C2F3E)),
    ]

    /// One negation of the letter: everything that decides one panel. The
    /// letter lives in the unit square, turned to stand the way the negation
    /// says, and the panel's frame places it.
    private struct Negation {
        /// Quarter turns: which way the letter stands.
        var turns: Int
        /// The corner the shadow is cast toward, one of the four diagonals.
        var cast: Int
        /// Where the crossbar and the stem reach, in the unit square. An edge
        /// at 0 or 1 runs off the panel, the way the paintings crop the letter.
        var top, left, right, bottom: Double
        var bar, stemWidth, stemCenter: Double
        /// The outline edges whose sides are painted, by index into `outline`.
        var faces: [Int]
        var family: Int
        /// Dark tone against the letter, light tone farthest from it.
        var reversed: Bool

        /// The discrete part: two negations with the same signature are the
        /// same painting to the eye, whatever their proportions.
        struct Signature: Hashable {
            var turns, cast, family: Int
            var faces: [Int]
            var reversed: Bool
        }

        var signature: Signature {
            Signature(turns: turns, cast: cast, family: family, faces: faces, reversed: reversed)
        }

        /// The four diagonals a shadow is cast along. Each step of depth moves
        /// the same distance along x and along y, which is what puts every cut
        /// at forty-five degrees.
        static let casts = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
        var direction: Vector2 { Negation.casts[cast] }

        /// The letter's outline, wound clockwise from the top left of the
        /// crossbar, then turned. The turn maps the unit square onto itself
        /// exactly, so a coordinate on an edge stays on it.
        var outline: [Vector2] {
            let yb = top + bar
            let s0 = stemCenter - stemWidth / 2, s1 = stemCenter + stemWidth / 2
            let upright = [Vector2(left, top), Vector2(right, top), Vector2(right, yb), Vector2(s1, yb),
                           Vector2(s1, bottom), Vector2(s0, bottom), Vector2(s0, yb), Vector2(left, yb)]
            return upright.map { point in
                var turned = point
                for _ in 0 ..< turns { turned = Vector2(1 - turned.y, turned.x) }
                return turned
            }
        }

        /// The outline edges whose side of the block faces the cast, leaving
        /// out any edge lying on or past the panel's edge, whose side could
        /// only be painted off the panel.
        static func lit(_ outline: [Vector2], toward direction: Vector2) -> [Int] {
            let area = signedArea(outline)
            return outline.indices.filter { i in
                let a = outline[i], b = outline[(i + 1) % outline.count]
                let edge = b - a
                let normal = area > 0 ? Vector2(edge.y, -edge.x) : Vector2(-edge.y, edge.x)
                guard normal.dot(direction) > 0 else { return false }
                let off = (a.x <= 0 && b.x <= 0) || (a.x >= 1 && b.x >= 1)
                    || (a.y <= 0 && b.y <= 0) || (a.y >= 1 && b.y >= 1)
                return !off
            }
        }

        /// Roll one negation. The sides painted are all the lit ones most of
        /// the time, else one unbroken run of them around the outline, and
        /// now and then a single one.
        static func roll<R: RandomNumberGenerator>(using rng: inout R, families: Int) -> Negation {
            var negation = Negation(
                turns: Int.random(in: 0 ... 3, using: &rng),
                cast: Int.random(in: 0 ... 3, using: &rng),
                top: 0, left: 0, right: 1, bottom: 1,
                bar: Double.random(in: 0.22 ... 0.34, using: &rng),
                stemWidth: Double.random(in: 0.24 ... 0.36, using: &rng),
                stemCenter: Double.random(in: 0.40 ... 0.60, using: &rng),
                faces: [],
                family: Int.random(in: 0 ..< families, using: &rng),
                reversed: Double.random(in: 0 ..< 1, using: &rng) < 0.3)
            negation.top = Double.random(in: 0 ..< 1, using: &rng) < 0.45
                ? 0 : Double.random(in: 0.08 ... 0.16, using: &rng)
            negation.left = Double.random(in: 0 ..< 1, using: &rng) < 0.3
                ? 0 : Double.random(in: 0.06 ... 0.12, using: &rng)
            negation.right = Double.random(in: 0 ..< 1, using: &rng) < 0.3
                ? 1 : Double.random(in: 0.84 ... 0.94, using: &rng)
            negation.bottom = Double.random(in: 0 ..< 1, using: &rng) < 0.15
                ? 1 : Double.random(in: 0.78 ... 0.92, using: &rng)

            let lit = Negation.lit(negation.outline, toward: negation.direction)
            let runs = Negation.runs(of: lit, around: 8)
            let choice = Double.random(in: 0 ..< 1, using: &rng)
            let long = runs.filter { $0.count >= 2 }
            if choice < 0.65 || long.isEmpty {
                negation.faces = lit
            } else if choice < 0.95 {
                let run = long[Int.random(in: 0 ..< long.count, using: &rng)]
                let length = Int.random(in: 2 ... run.count, using: &rng)
                let start = Int.random(in: 0 ... run.count - length, using: &rng)
                negation.faces = Array(run[start ..< start + length])
            } else {
                negation.faces = [lit[Int.random(in: 0 ..< lit.count, using: &rng)]]
            }
            return negation
        }

        /// The unbroken runs of lit edges around the outline, each in
        /// outline order.
        static func runs(of lit: [Int], around count: Int) -> [[Int]] {
            let set = Set(lit)
            guard !set.isEmpty, set.count < count else { return set.isEmpty ? [] : [lit.sorted()] }
            var runs: [[Int]] = []
            for start in 0 ..< count where set.contains(start) && !set.contains((start + count - 1) % count) {
                var run = [start]
                var next = (start + 1) % count
                while set.contains(next) && next != start {
                    run.append(next)
                    next = (next + 1) % count
                }
                runs.append(run)
            }
            return runs
        }

        static func signedArea(_ points: [Vector2]) -> Double {
            var sum = 0.0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                sum += a.x * b.y - b.x * a.y
            }
            return sum / 2
        }
    }

    /// A panel on the wall: what hangs there, what hung there before, and
    /// when the painting over began. A negative time is a panel that was
    /// there when the wall went up.
    private struct Panel {
        var current: Negation
        var previous: Negation?
        var since: Double
    }

    private var panels: [Panel] = []
    /// The order the panels are painted over in, a shuffle of the wall.
    private var order: [Int] = []
    private var built = (variation: Int.min, across: 0)
    /// Every painting over so far, the ones the clock called for, and the
    /// presses not yet answered.
    private var painted = 0
    private var timed = 0
    private var pressed = 0

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(wall)
        let count = across * across
        if built.variation != variation || built.across != across || panels.count != count {
            rebuild(count: count)
        }
        while timed < Int(time / pace) {
            timed += 1
            repaint(at: Double(timed) * pace)
        }
        while pressed > 0 {
            pressed -= 1
            repaint(at: time)
        }

        let cells = plateGrid(columns: across, rows: across).cells
        for (i, cell) in cells.enumerated() where i < panels.count {
            let panel = panels[i]
            let progress = panel.since < 0 ? 1.0 : min(1.0, (time - panel.since) / brush)
            if let previous = panel.previous, progress < 1 {
                draw(previous, in: cell.frame, progress: 1)
            }
            draw(panel.current, in: cell.frame, progress: progress)
        }
    }

    /// Hang the wall: one negation per panel, none alike, and the order they
    /// will be painted over in.
    private func rebuild(count: Int) {
        built = (variation, across)
        var rng = SplitMix64(seed: seed(panel: -1, generation: 0))
        order = (0 ..< count).shuffled(using: &rng)
        panels = []
        for panel in 0 ..< count {
            let fresh = roll(panel: panel, generation: 0, avoiding: panels.map(\.current))
            panels.append(Panel(current: fresh, previous: nil, since: -1))
        }
        painted = 0
        timed = 0
        pressed = 0
    }

    /// Paint the next panel over with a negation unlike any on the wall.
    private func repaint(at time: Double) {
        guard !panels.isEmpty else { return }
        let panel = order[painted % panels.count]
        let generation = painted / panels.count + 1
        let fresh = roll(panel: panel, generation: generation, avoiding: panels.map(\.current))
        panels[panel] = Panel(current: fresh, previous: panels[panel].current, since: time)
        painted += 1
    }

    /// Roll a negation for one panel and one painting of it, rejecting any
    /// that matches a panel already on the wall.
    private func roll(panel: Int, generation: Int, avoiding shown: [Negation]) -> Negation {
        var rng = SplitMix64(seed: seed(panel: panel, generation: generation))
        let taken = Set(shown.map(\.signature))
        var fresh = Negation.roll(using: &rng, families: Negaciones.families.count)
        var tries = 0
        while (taken.contains(fresh.signature) || fresh.faces.isEmpty) && tries < 64 {
            fresh = Negation.roll(using: &rng, families: Negaciones.families.count)
            tries += 1
        }
        return fresh
    }

    private func seed(panel: Int, generation: Int) -> UInt64 {
        let mixed = variation &* 1_000_003 &+ (panel &+ 2) &* 7919 &+ generation &* 104_729
        return UInt64(bitPattern: Int64(mixed))
    }

    /// Paint one negation into a panel. `progress` runs from 0 to 1 while the
    /// panel is being painted over: the ground rolls down the panel first,
    /// then the tones are laid from the deepest one inward, and the letter's
    /// own face goes on last in the ground's color. Deeper tones go down
    /// first because where two sides of the block overlap, the one nearer
    /// the letter is the one in front.
    private func draw(_ negation: Negation, in frame: Rectangle, progress: Double) {
        let family = Negaciones.families[negation.family]
        noStroke()
        fill(family.ground)
        if progress < 1 {
            drawRect(frame.x, frame.y, frame.width, frame.height * min(1, progress / 0.4))
        } else {
            drawRect(frame)
        }

        let outline = negation.outline
        let direction = negation.direction
        let step = depth / Double(stripes)
        let (near, far) = negation.reversed ? (family.far, family.near) : (family.near, family.far)
        for k in stride(from: stripes - 1, through: 0, by: -1) {
            let appears = 0.45 + 0.5 * Double(stripes - 1 - k) / Double(stripes)
            guard progress >= appears else { continue }
            fill(near.mixed(with: far, Double(k) / Double(max(1, stripes - 1))))
            for i in negation.faces {
                let a = outline[i], b = outline[(i + 1) % outline.count]
                let inner = direction * (Double(k) * step)
                let outer = direction * (Double(k + 1) * step)
                let side = Negaciones.clipToUnit([a + inner, b + inner, b + outer, a + outer])
                guard side.count >= 3 else { continue }
                drawPolygon(side.map { place($0, in: frame) })
            }
        }

        // The letter is a concave outline, so it goes through the shape
        // path, which triangulates it, rather than the polygon fan.
        if progress >= 0.45 {
            fill(family.ground)
            let letter = Negaciones.clipToUnit(outline)
            if letter.count >= 3 {
                drawShape(Shape(letter.map { place($0, in: frame) }))
            }
        }
    }

    private func place(_ point: Vector2, in frame: Rectangle) -> Vector2 {
        Vector2(frame.x + point.x * frame.width, frame.y + point.y * frame.height)
    }

    /// Cut a polygon down to the unit square, one edge of the square at a
    /// time, so nothing is painted past a panel and the file holds only what
    /// shows.
    private static func clipToUnit(_ polygon: [Vector2]) -> [Vector2] {
        var kept = polygon
        kept = clip(kept, keep: { $0.x >= 0 }) { a, b in cross(a, b, x: 0) }
        kept = clip(kept, keep: { $0.x <= 1 }) { a, b in cross(a, b, x: 1) }
        kept = clip(kept, keep: { $0.y >= 0 }) { a, b in cross(a, b, y: 0) }
        kept = clip(kept, keep: { $0.y <= 1 }) { a, b in cross(a, b, y: 1) }
        return kept
    }

    private static func clip(_ polygon: [Vector2], keep: (Vector2) -> Bool,
                             cross: (Vector2, Vector2) -> Vector2) -> [Vector2] {
        guard !polygon.isEmpty else { return [] }
        var out: [Vector2] = []
        var previous = polygon[polygon.count - 1]
        for point in polygon {
            let inside = keep(point), wasInside = keep(previous)
            if inside {
                if !wasInside { out.append(cross(previous, point)) }
                out.append(point)
            } else if wasInside {
                out.append(cross(previous, point))
            }
            previous = point
        }
        return out
    }

    private static func cross(_ a: Vector2, _ b: Vector2, x: Double) -> Vector2 {
        let t = (x - a.x) / (b.x - a.x)
        return Vector2(x, a.y + (b.y - a.y) * t)
    }

    private static func cross(_ a: Vector2, _ b: Vector2, y: Double) -> Vector2 {
        let t = (y - a.y) / (b.y - a.y)
        return Vector2(a.x + (b.x - a.x) * t, y)
    }

    private func plateGrid(columns: Int, rows: Int) -> Grid {
        let room = Rectangle(center: center, width: width * 0.9, height: height * 0.9)
        let cell = min(room.width / Double(columns), room.height / Double(rows))
        let block = Rectangle(center: center,
                              width: cell * Double(columns), height: cell * Double(rows))
        return Grid(in: block, columns: columns, rows: rows, gutter: cell * 0.08)
    }
}
