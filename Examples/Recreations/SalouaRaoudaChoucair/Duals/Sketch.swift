//  Recreation after Saloua Raouda Choucair - the Duals (thana'ia), the
//  sculptures in two parts she made from 1975 into the late 1980s, read from
//  Dual (1975-77; fiberglass over clay, Smith College Museum of Art) and
//  Untitled, from the Repetitive Dual series (conceived 1988-90, cast in
//  aluminum in 2011): two pieces that lock into one block and stand apart as
//  two. A homage, not a reproduction, and not affiliated with or endorsed by
//  the artist or her estate.
//  https://scma.smith.edu/blog/new-acquisition-saloua-raouda-choucair
//  https://www.tate.org.uk/whats-on/tate-modern/exhibition/saloua-raouda-choucair
//
//  An original Ollin interpretation, written from the sculptures. Nothing was
//  ported: the work is carved, cast and shaped by hand, and the rule below
//  is a reading of how the two parts meet, not a plan of any one piece.

import Foundation
import Ollin

/// The Duals (Saloua Raouda Choucair, Beirut). From 1975 she made sculptures
/// in two parts, each called *Dual*: two forms that close on each other so
/// exactly that the join is a line, and that can be set side by side as two.
/// In the *Repetitive Dual* series a block is split down its height by a cut
/// that steps from side to side, every step a tooth, so the halves interlock
/// like the fingers of two hands; other Duals are softer, one form lying over
/// the other like a lid.
///
/// This sketch keeps the rule: one block, one cut. The block is ruled into a
/// grid of cells, and the cut runs from edge to edge with every corner on a
/// grid point. The cut is a graph: it crosses every line running one way
/// exactly once, which is what lets the parts come apart at all, since a part
/// slid off along that way never meets the other. The two parts are the block
/// cut by the region on one side of the line and the block minus it, so
/// together they are the block and they share nothing but the cut. `look`
/// picks the cut: `comb` the stepped teeth of the *Repetitive Dual* in
/// aluminum on white, `key` a softened slab of wood cut along its length with
/// keys in the joint, and `stair` a square of painted wood cut by a staircase
/// from one edge to the other. The seed deals the teeth, the keys or the
/// steps.
///
/// The parts slide apart along their free direction until a straight line
/// separates them (`clearance` cells more than the cut's depth), then each
/// leans away about its own outer corner, which never brings a point of it
/// nearer the other; they hold, lean back, slide in, and lock. A new lean is
/// dealt each cycle; `lean` scales it. `seam` draws each part a hair inside
/// its outline in the round, in cells, so the join reads as the line it is on
/// the sculpture. `view` shows the block lit in the round (`object`) or flat
/// (`plan`, true outlines that `--export-svg` writes, with the grid drawn over
/// them by `showGrid`), and both views move the same way.
@main
final class Duals: Sketch {
    enum Look: String, CaseIterable, ParamOption { case comb, key, stair }
    enum View: String, CaseIterable, ParamOption { case object, plan }

    @Param(icon: "square.split.2x1") var look = Look.comb
    @Param(icon: "eye") var view = View.object
    @Param(0.2 ... 2.5, icon: "arrow.left.and.right") var clearance = 0.6
    @Param(0 ... 2, icon: "angle") var lean = 1.0
    @Param(0 ... 0.3, icon: "line.horizontal.3") var seam = 0.1
    @Param(8 ... 40, icon: "clock") var seconds = 16.0
    @Param(icon: "grid") var showGrid = false

    override var loopDuration: Double? { seconds }

    /// The block in grid cells, the cut, the two parts, and how they move.
    private struct Block {
        var columns = 10
        var rows = 14
        /// The cut, from edge to edge, every vertex a grid point.
        var cut: [Vector2] = []
        /// The part on the near side of the cut, and the part past it, in cells
        /// with y up.
        var near = Shape([])
        var far = Shape([])
        /// The side of the cut the far part is on: the cut is a graph across
        /// this axis, so a line along it crosses the cut once.
        var side = Vector2(1, 0)
        /// The free direction (the far part leaves along it) and the axis
        /// across it, both unit.
        var free = Vector2(1, 0)
        var across = Vector2(0, 1)
        /// Whether the near part moves too, or stays where it stands.
        var bothMove = true
        /// How far apart the parts go: the cut's depth along the free
        /// direction plus the clearance.
        var travel = 0.0
        /// The lean, in radians, before `lean` scales it.
        var leanRange = 0.1 ... 0.2
        var depth = 6.0
        var corner = 0.0
    }

    private struct Finish {
        var ground: Color
        var face: Color
        var seam: Color
        var material: Material
        /// How bright the studio the surfaces reflect is.
        var studio: Double
    }

    private var block = Block()
    private var finish = Finish(ground: .white, face: .gray, seam: .black, material: .matte, studio: 0.5)
    private var builtFor = ""

    override func draw() {
        let key = "\(look)/\(variation)/\(clearance)"
        if key != builtFor {
            block = build()
            finish = Duals.finish(look)
            builtFor = key
        }
        let (near, far) = pose(at: time)
        if view == .plan {
            drawPlan(near, far)
        } else {
            drawObject(near, far)
        }
    }

    // MARK: The block and its cut

    private func build() -> Block {
        // The same seed deals the same cut whatever was changed before.
        seed(variation)
        var block = Block()
        switch look {
        case .comb:
            // Down the height of a tall block, a tooth a row, each reaching one
            // way or the other from the middle column by one or two cells.
            block.columns = 10
            block.rows = 14
            let middle = Double(block.columns / 2)
            var cut: [Vector2] = []
            var side = random() < 0.5 ? 1.0 : -1.0
            for row in 0 ..< block.rows {
                let reach = random() < 0.3 ? 2.0 : 1.0
                let x = middle + side * reach
                cut.append(Vector2(x, Double(row)))
                cut.append(Vector2(x, Double(row + 1)))
                side = -side
            }
            block.cut = cut
            block.side = Vector2(1, 0)
            block.free = Vector2(1, 0)
            block.across = Vector2(0, 1)
            block.bothMove = true
            block.leanRange = 0.07 ... 0.14
            block.depth = 6
        case .key:
            // Along a slab, a joint at mid height with two or three keys in it,
            // each a trapezoid one or two rows deep with square or slanted sides.
            block.columns = 20
            block.rows = 8
            let base = 4.0
            var cut = [Vector2(0, base)]
            let keys = random() < 0.5 ? 2 : 3
            var x = Int(random(1, 3))
            for k in 0 ..< keys {
                let left = keys - k - 1
                let roomLeft = block.columns - 1 - x - left * 5
                guard roomLeft >= 3 else { break }
                let width = min(Int(random(3, 6)), roomLeft)
                let rise = (random() < 0.5 ? 1.0 : -1.0) * (random() < 0.4 ? 2.0 : 1.0)
                let slant = width >= 3 && random() < 0.6 ? 1 : 0
                cut.append(Vector2(Double(x), base))
                cut.append(Vector2(Double(x + slant), base + rise))
                cut.append(Vector2(Double(x + width - slant), base + rise))
                cut.append(Vector2(Double(x + width), base))
                let spare = block.columns - 1 - (x + width) - left * 5
                x += width + 2 + Int(random(0, Double(max(spare - 1, 0)) / Double(max(left, 1)) + 1))
            }
            cut.append(Vector2(Double(block.columns), base))
            block.cut = cut
            block.side = Vector2(0, 1)
            block.free = Vector2(0, 1)
            block.across = random() < 0.5 ? Vector2(1, 0) : Vector2(-1, 0)
            block.bothMove = false
            block.leanRange = 0.12 ... 0.24
            block.depth = 4
            block.corner = 0.8
        case .stair:
            // A staircase across a square, from high on the left edge to low on
            // the right, runs of one to three cells and drops of one or two.
            block.columns = 12
            block.rows = 12
            var runs: [Int] = []
            var total = 0
            while total < block.columns {
                let run = min(Int(random(1, 4)), block.columns - total)
                runs.append(run)
                total += run
            }
            var drops: [Int] = (0 ..< max(runs.count - 1, 0)).map { _ in random() < 0.6 ? 1 : 2 }
            while drops.reduce(0, +) > block.rows - 3, let i = drops.firstIndex(of: 2) { drops[i] = 1 }
            let fall = drops.reduce(0, +)
            let low = Int(random(2, Double(max(block.rows - 1 - fall, 2)) + 1))
            var y = Double(min(low + fall, block.rows - 1))
            var x = 0.0
            var cut = [Vector2(0, y)]
            for (i, run) in runs.enumerated() {
                x += Double(run)
                cut.append(Vector2(x, y))
                if i < drops.count {
                    y -= Double(drops[i])
                    cut.append(Vector2(x, y))
                }
            }
            block.cut = cut
            // The far part is above the stairs, and it leaves up and to the right:
            // the stairs only ever fall, so nothing above them meets them that way.
            block.side = Vector2(0, 1)
            let diagonal = 1 / 2.0.squareRoot()
            block.free = Vector2(diagonal, diagonal)
            block.across = Vector2(diagonal, -diagonal)
            block.bothMove = false
            block.leanRange = 0.09 ... 0.18
            block.depth = 3
        }

        // The parts: the block on the far side of the cut, and the rest of it.
        // The far side is the region from the cut out across it, closed well
        // beyond the block.
        let whole = Shape(Duals.outline(columns: block.columns, rows: block.rows, corner: block.corner), closed: true)
        var outline = block.cut
        let reach = Double(block.columns + block.rows) * 2
        if let first = block.cut.first, let last = block.cut.last {
            outline.append(last + block.side * reach)
            outline.append(first + block.side * reach)
        }
        let beyond = Shape(outline, closed: true)
        block.far = whole.intersection(beyond)
        block.near = whole.subtracting(beyond)

        // How deep the cut runs along the free direction is how far apart the
        // parts must go before a line can pass between them.
        let along = block.cut.map { $0.dot(block.free) }
        block.travel = (along.max() ?? 0) - (along.min() ?? 0) + clearance
        return block
    }

    /// The block's outline, its corners rounded into arcs of twelve segments
    /// when `corner` is more than zero.
    private static func outline(columns: Int, rows: Int, corner: Double) -> [Vector2] {
        let w = Double(columns), h = Double(rows)
        guard corner > 0 else { return [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)] }
        let centers = [Vector2(w - corner, corner), Vector2(w - corner, h - corner),
                       Vector2(corner, h - corner), Vector2(corner, corner)]
        var points: [Vector2] = []
        for (i, c) in centers.enumerated() {
            let start = Double(i - 1) * .pi / 2
            for step in 0 ... 12 {
                let a = start + Double(step) / 12 * .pi / 2
                points.append(c + Vector2(cos(a), sin(a)) * corner)
            }
        }
        return points
    }

    // MARK: The motion

    /// Both parts at `time`: slid apart, leaned, held, and back. Each part only
    /// ever moves away from the other, so they meet again only at the lock.
    private func pose(at time: Double) -> (Shape, Shape) {
        let cycle = Int((time / seconds).rounded(.down))
        let phase = time / seconds - Double(cycle)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 7919 &+ cycle &* 104_729 &+ 31)))
        let angle = Double.random(in: block.leanRange, using: &rng) * lean

        func ease(_ a: Double, _ b: Double) -> Double {
            let t = min(max((phase - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        let slide = ease(0.12, 0.34) * (1 - ease(0.80, 0.96))
        let turn = ease(0.36, 0.52) * (1 - ease(0.64, 0.78))
        return posed(slide: slide, angle: angle * turn)
    }

    /// The parts with `slide` of the travel taken and leaned by `angle`.
    private func posed(slide: Double, angle: Double) -> (Shape, Shape) {
        let farShift = block.free * (block.travel * slide * (block.bothMove ? 0.5 : 1))
        let nearShift = block.free * (block.bothMove ? -block.travel * slide * 0.5 : 0)
        let far = moved(block.far, by: farShift, leaning: angle, isFar: true)
        let near = block.bothMove ? moved(block.near, by: nearShift, leaning: angle, isFar: false) : block.near
        return (near, far)
    }

    /// The bounds, in cells, of the block and of the parts at their widest.
    private func reach() -> (min: Vector2, max: Vector2) {
        let (near, far) = posed(slide: 1, angle: block.leanRange.upperBound * max(lean, 1))
        let points = [block.near, block.far, near, far].flatMap { $0.contours.flatMap(\.points) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return (Vector2(xs.min() ?? 0, ys.min() ?? 0), Vector2(xs.max() ?? 1, ys.max() ?? 1))
    }

    /// A part slid by `shift` and then turned by `angle` about the corner of its
    /// own bounds (across the free direction, and along it) that keeps every
    /// point on its own side: the far part about its lowest corner across and
    /// its highest along, turned so its far end lifts away; the near part
    /// about its lowest corner on both, turned the other way.
    private func moved(_ part: Shape, by shift: Vector2, leaning angle: Double, isFar: Bool) -> Shape {
        let slid = part.mapPoints { $0 + shift }
        guard angle != 0 else { return slid }
        let u = block.across, v = block.free
        let points = slid.contours.flatMap(\.points)
        let us = points.map { $0.dot(u) }, vs = points.map { $0.dot(v) }
        let pivot = Vector2(us.min() ?? 0, isFar ? (vs.max() ?? 0) : (vs.min() ?? 0))
        let turn = isFar ? angle : -angle
        let c = cos(turn), s = sin(turn)
        return slid.mapPoints { p in
            let du = p.dot(u) - pivot.x, dv = p.dot(v) - pivot.y
            let ru = pivot.x + du * c - dv * s
            let rv = pivot.y + du * s + dv * c
            return u * ru + v * rv
        }
    }

    // MARK: Drawing

    /// Cells to canvas: the parts at their widest fitted to the canvas, y
    /// turned down.
    private func layout() -> (cell: Double, origin: Vector2) {
        let (low, high) = reach()
        let span = high - low
        let cell = min(width / span.x, height / span.y) * 0.84
        let middle = (low + high) * 0.5
        return (cell, Vector2(center.x - middle.x * cell, center.y + middle.y * cell))
    }

    private func drawPlan(_ near: Shape, _ far: Shape) {
        background(finish.ground)
        let (cell, origin) = layout()
        let toCanvas = { (p: Vector2) in Vector2(origin.x + p.x * cell, origin.y - p.y * cell) }
        fill(finish.face)
        stroke(finish.seam)
        strokeWeight(max(cell * 0.06, 1.5))
        strokeJoin(.miter)
        for part in [near, far] {
            drawShape(part.mapPoints(toCanvas))
        }
        // The grid the cut was drawn on, over the block where it stands at the
        // lock, so every corner of the cut can be seen on a grid point.
        if showGrid {
            stroke(finish.seam.withAlpha(0.3))
            strokeWeight(1)
            for c in 0 ... block.columns {
                drawLine(toCanvas(Vector2(Double(c), 0)), toCanvas(Vector2(Double(c), Double(block.rows))))
            }
            for r in 0 ... block.rows {
                drawLine(toCanvas(Vector2(0, Double(r))), toCanvas(Vector2(Double(block.columns), Double(r))))
            }
        }
    }

    private func drawObject(_ near: Shape, _ far: Shape) {
        background(finish.ground)
        let scale = 1.0 / Double(max(block.columns, block.rows))
        let middle = Double(block.columns) / 2
        let toWorld = { (p: Vector2) in Vector2((p.x - middle) * scale, p.y * scale) }
        let depth = block.depth * scale

        // A slow look round from the front and a little above, at the parts
        // at their widest.
        let (low, high) = reach()
        let focus = toWorld((low + high) * 0.5)
        let span = max(high.x - low.x, high.y - low.y) * scale
        let sway = sin(time * 2 * .pi / seconds) * 0.35 + 0.42
        let distance = span * 2.3 + depth
        let eye = Vector3(sin(sway) * distance, focus.y + distance * 0.38, cos(sway) * distance)
        perspective(eye: eye, target: Vector3(focus.x, focus.y, 0), fieldOfView: 0.62)

        environment(.studio.intensified(to: finish.studio).lightingOnly())
        toneMap(.aces)
        ambientLight(Color(white: 0.08))
        directionalLight(Color(red: 1, green: 0.96, blue: 0.9), direction: Vector3(-0.45, -0.8, -0.5).normalized,
                         intensity: 1.6, softness: 0.3)
        directionalLight(Color(white: 0.8), direction: Vector3(0.6, -0.3, -0.4).normalized,
                         intensity: 0.25, castsShadow: false)
        castShadows()

        withState {
            translate(0, -0.01, 0)
            fill(finish.ground)
            material(.matte)
            drawBox(width: 8, height: 0.02, depth: 8)
        }
        // Each part is drawn a hair inside its outline, so the join reads as
        // the line it is on the sculpture; the plan keeps the true outlines.
        noStroke()
        fill(finish.face)
        material(finish.material)
        for part in [near, far] {
            let solid = seam > 0 ? part.offset(by: -seam / 2, join: .miter) : part
            drawExtrude(solid.mapPoints(toWorld), depth: depth)
        }
    }

    private static func finish(_ look: Look) -> Finish {
        switch look {
        case .comb:
            return Finish(ground: Color(white: 0.94), face: Color(red: 0.80, green: 0.81, blue: 0.83),
                          seam: Color(white: 0.35), material: .physicallyBased(metallic: 0.6, roughness: 0.32), studio: 1.0)
        case .key:
            return Finish(ground: Color(white: 0.60), face: Color(red: 0.52, green: 0.30, blue: 0.19),
                          seam: Color(red: 0.22, green: 0.12, blue: 0.07), material: .satin, studio: 0.5)
        case .stair:
            return Finish(ground: Color(white: 0.40), face: Color(red: 0.93, green: 0.92, blue: 0.89),
                          seam: Color(white: 0.55), material: .matte, studio: 0.5)
        }
    }
}
