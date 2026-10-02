//  Recreation after Saloua Raouda Choucair - the Poems (qasa'id), the
//  stacked sculptures she began in the 1960s, read from Poem (1963-65, wood;
//  Tate), the six stone verses of Poem (1963-65; Centre Pompidou), Infinite
//  Structure (1963-65, tufa stone; Tate) and Poem of Nine Verses (1966-68,
//  aluminum; Tate): blocks that stand one on another, each shaped to the one
//  below, each able to stand alone. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or her estate.
//  https://www.tate.org.uk/art/artworks/choucair-poem-t13278
//  https://www.tate.org.uk/art/artworks/choucair-poem-of-nine-verses-t13647
//  https://www.tate.org.uk/whats-on/tate-modern/exhibition/saloua-raouda-choucair
//
//  An original Ollin interpretation, written from the sculptures. Nothing was
//  ported: the work is carved and cast by hand, and the rule below is a
//  reading of how the verses meet, not a plan of any one piece.

import Foundation
import Ollin

/// The Poems (Saloua Raouda Choucair, Beirut). In the 1960s she made
/// sculptures of separate units stacked one on another, the *qasa'id*, poems:
/// in the classical Arabic ode each verse is complete in itself and the poem
/// is their sequence, and each of her units stands on its own and reads as
/// part of the whole when it is set on the one below. The face where two meet is shaped so they fit: a step, a
/// notch, a tongue, sometimes a long slant, and the units have windows cut
/// through them.
///
/// This sketch keeps the rule: one block, cut into verses. The block is ruled
/// into a grid of cells; each cut runs across it with every corner on a grid
/// point, level but for keys one row up or down, square or slanted at their
/// sides, and some reaching the edge as a step. Each verse is the block
/// between two cuts, so the verses fill the block exactly and share only
/// their joints. Some verses have windows cut through them, rectangles on
/// the grid kept a cell clear of every edge. `look` picks the poem: `wood`
/// five verses with windows (after the wooden *Poem*), `stone` six tall
/// verses of tufa (after the stone *Poem* and *Infinite Structure*), and
/// `aluminum` nine thin slabs keyed together (after *Poem of Nine Verses*).
/// The seed deals the keys and the windows.
///
/// The poem is lifted apart: each verse rises above the one under it by more
/// than any key is deep, so a verse can then turn and slide without meeting
/// its neighbors; each turns about its own upright by a dealt angle and
/// slides along the block by a dealt number of cells, holds while the light
/// moves over it, turns back, and is set down into the block again. A new
/// reading is dealt each cycle. `rise` is the gap between lifted verses in
/// rows, `turn` scales the dealt turns, and `unlit` puts the lights out.
/// `seam` sets each solid a hair inside its verse, in cells, so the
/// joints read as lines; at 0 the solids fit exactly, and `--export-usdz`
/// writes them as separate solids that make the block again.
@main
final class Poem: Sketch {
    enum Look: String, CaseIterable, ParamOption { case wood, stone, aluminum }

    @Param(icon: "square.stack.3d.up") var look = Look.wood
    @Param(0.2 ... 3, icon: "arrow.up.and.down") var rise = 0.8
    @Param(0 ... 2, icon: "rotate.3d") var turn = 1.0
    @Param(0 ... 0.3, icon: "line.horizontal.3") var seam = 0.08
    @Param(12 ... 60, icon: "clock") var seconds = 24.0
    @Param(icon: "lightbulb.slash") var unlit = false

    override var canvasSize: CanvasSize { .size(1080, 1350) }
    override var loopDuration: Double? { seconds }

    /// The rule for one look: the grid, how the cuts are keyed, and the finish.
    private struct Rule {
        var verses: Int
        var columns: Int
        var rowsPerVerse: Int
        var depth: Int
        var keys: ClosedRange<Int>
        var keyWidth: ClosedRange<Int>
        var windows: ClosedRange<Int>
        var slide: Double
        var turn: Double
        var ground: Color
        var face: Color
        var material: Material
    }

    /// A verse: its solid, built about its own center, and where that center is.
    private struct Verse {
        var mesh: Mesh
        var center: Vector2
        var outline: [Vector2]
        var windows: [[Vector2]]
    }

    private var rule = Poem.rule(.wood)
    private var verses: [Verse] = []
    private var cell = 0.1
    private var builtFor = ""

    override func draw() {
        let key = "\(look)/\(variation)/\(seam)"
        if key != builtFor {
            rule = Poem.rule(look)
            build()
            builtFor = key
        }

        background(rule.ground)
        let height = Double(rule.verses * rule.rowsPerVerse) * cell
        let (lifts, slides, turns) = reading(at: time)

        // A slow walk round the front of the stack, a little above it, framed
        // on the poem lifted to its full height.
        let tallest = height + Double(rule.verses - 1) * (2 + rise) * cell
        // One sway a cycle, so the loop closes; the hold is seen from the front.
        let sway = sin(time * 2 * .pi / seconds) * 0.45 + 0.3
        let target = Vector3(0, tallest * 0.5, 0)
        let distance = tallest * 2.05
        let eye = target + Vector3(sin(sway) * distance, distance * 0.16, cos(sway) * distance)
        perspective(eye: eye, target: target, fieldOfView: 0.62)
        light()

        withState {
            translate(0, -0.01, 0)
            fill(rule.ground)
            material(.matte)
            drawBox(width: 10, height: 0.02, depth: 10)
        }
        noStroke()
        fill(rule.face)
        material(rule.material)
        for (k, verse) in verses.enumerated() {
            withState {
                translate(verse.center.x + slides[k], verse.center.y + lifts[k], 0)
                rotateY(turns[k])
                drawMesh(verse.mesh)
            }
        }
    }

    private func light() {
        if unlit {
            noLights()
            return
        }
        environment(.studio.intensified(to: 0.45).lightingOnly())
        toneMap(.aces)
        ambientLight(Color(white: 0.07))
        // A key from high on the left that drifts across the front over the
        // cycle, so the windows and joints throw shadows that turn.
        let drift = sin(time * 2 * .pi / seconds) * 0.5
        let key = Vector3(-0.55 + drift, -0.75, -0.45).normalized
        directionalLight(Color(red: 1, green: 0.95, blue: 0.88), direction: key, intensity: 1.7, softness: 0.25)
        directionalLight(Color(white: 0.75), direction: Vector3(0.7, -0.2, -0.5).normalized,
                         intensity: 0.25, castsShadow: false)
        castShadows()
    }

    // MARK: The block and its cuts

    private func build() {
        // The same seed deals the same poem whatever was changed before.
        seed(variation)
        let rows = rule.verses * rule.rowsPerVerse
        cell = 1.0 / Double(max(rows, rule.columns))

        // Each cut is a level for every column edge to edge: a polyline whose
        // corners are grid points. A key lifts or drops a run of columns by one
        // row, its sides square or slanted by one column.
        var cuts: [[Vector2]] = [[Vector2(0, 0), Vector2(Double(rule.columns), 0)]]
        for k in 1 ..< rule.verses {
            cuts.append(keyedCut(base: Double(k * rule.rowsPerVerse)))
        }
        cuts.append([Vector2(0, Double(rows)), Vector2(Double(rule.columns), Double(rows))])

        verses = []
        for k in 0 ..< rule.verses {
            let lower = cuts[k], upper = cuts[k + 1]
            // Up the right edge, back along the upper cut, down the left edge.
            let outline = lower + upper.reversed()
            let windows = cutWindows(lower: lower, upper: upper)
            let middle = Vector2(Double(rule.columns) / 2, Double(k * rule.rowsPerVerse) + Double(rule.rowsPerVerse) / 2)
            let local = { (p: Vector2) in (p - middle) * self.cell }
            // Each solid stands a hair inside its verse, so the joints read as
            // the lines they are on the sculpture; at no seam they fit exactly.
            var shape = Shape(outer: outline.map(local), holes: windows.map { $0.map(local) })
            if seam > 0 { shape = shape.offset(by: -seam / 2 * cell, join: .miter) }
            verses.append(Verse(mesh: Mesh.extrude(shape, depth: Double(rule.depth) * cell),
                                center: Vector2(0, middle.y * cell),
                                outline: outline, windows: windows))
        }
    }

    private func keyedCut(base: Double) -> [Vector2] {
        let columns = rule.columns
        var points = [Vector2(0, base)]
        var x = 0
        var keysLeft = Int(random(Double(rule.keys.lowerBound), Double(rule.keys.upperBound) + 1))
        while keysLeft > 0 {
            // Room for this key and the rest, each at least its width and a gap.
            let roomForRest = (keysLeft - 1) * (rule.keyWidth.lowerBound + 1)
            let latest = columns - roomForRest - rule.keyWidth.lowerBound
            guard latest >= x else { break }
            let earliest = max(x, 1)
            let start = x == 0 && random() < 0.25 ? 0 : Int(random(Double(earliest), Double(max(latest, earliest)) + 1))
            let widest = min(rule.keyWidth.upperBound, columns - roomForRest - start)
            guard widest >= rule.keyWidth.lowerBound else { break }
            var width = Int(random(Double(rule.keyWidth.lowerBound), Double(widest) + 1))
            // The last key may run out to the edge, which makes it a step.
            if keysLeft == 1, columns - (start + width) <= 2, random() < 0.5 { width = columns - start }
            let rise = random() < 0.5 ? 1.0 : -1.0
            let slant = width >= 3 && random() < 0.5 ? 1 : 0
            let left = Double(start), right = Double(start + width)
            let atLeftEdge = start == 0, atRightEdge = start + width == columns
            if atLeftEdge {
                points[0] = Vector2(0, base + rise)
            } else {
                points.append(Vector2(left, base))
                points.append(Vector2(left + Double(slant), base + rise))
            }
            if atRightEdge {
                points.append(Vector2(right, base + rise))
                return points
            }
            points.append(Vector2(right - Double(slant), base + rise))
            points.append(Vector2(right, base))
            x = start + width + 1
            keysLeft -= 1
        }
        points.append(Vector2(Double(columns), base))
        return points
    }

    /// Windows through a verse: rectangles on the grid, each a cell clear of
    /// the verse's edges and of each other.
    private func cutWindows(lower: [Vector2], upper: [Vector2]) -> [[Vector2]] {
        let count = Int(random(Double(rule.windows.lowerBound), Double(rule.windows.upperBound) + 1))
        guard count > 0 else { return [] }
        var windows: [[Vector2]] = []
        var taken: [ClosedRange<Int>] = []
        for _ in 0 ..< count * 6 where windows.count < count {
            let w = Int(random(2, Double(max(rule.columns / 3, 3)) + 1))
            let x0 = Int(random(1, Double(rule.columns - 1 - w) + 1))
            let x1 = x0 + w
            guard x1 <= rule.columns - 1, !taken.contains(where: { $0.overlaps(x0 - 1 ... x1) }) else { continue }
            // The cuts' highest and lowest levels over the window and a column
            // either side bound it.
            let floor = level(of: lower, from: Double(x0 - 1), to: Double(x1 + 1), highest: true) + 1
            let ceiling = level(of: upper, from: Double(x0 - 1), to: Double(x1 + 1), highest: false) - 1
            let room = Int(ceiling - floor)
            guard room >= 1 else { continue }
            let h = Int(random(1, Double(min(room, max(rule.rowsPerVerse / 2, 1))) + 1))
            let y0 = floor + Double(Int(random(0, Double(room - h) + 1)))
            let y1 = y0 + Double(h)
            windows.append([Vector2(Double(x0), y0), Vector2(Double(x0), y1), Vector2(Double(x1), y1), Vector2(Double(x1), y0)])
            taken.append(x0 ... x1)
        }
        return windows
    }

    /// The highest (or lowest) level a cut reaches between two columns.
    private func level(of cut: [Vector2], from a: Double, to b: Double, highest: Bool) -> Double {
        var levels: [Double] = []
        for i in 0 ..< cut.count - 1 {
            let p = cut[i], q = cut[i + 1]
            if max(p.x, q.x) < a || min(p.x, q.x) > b { continue }
            levels.append(p.y)
            levels.append(q.y)
        }
        return (highest ? levels.max() : levels.min()) ?? cut[0].y
    }

    // MARK: The reading

    /// How high each verse is lifted, how far it slides, and how far it turns
    /// at `time`. The lift comes first and goes last, and each verse clears the
    /// one below by more than a key is deep before it turns.
    private func reading(at time: Double) -> ([Double], [Double], [Double]) {
        let cycle = Int((time / seconds).rounded(.down))
        let phase = time / seconds - Double(cycle)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 6271 &+ cycle &* 92_821 &+ 7)))

        func ease(_ a: Double, _ b: Double) -> Double {
            let t = min(max((phase - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        let up = ease(0.10, 0.28) * (1 - ease(0.84, 0.97))
        let swing = ease(0.30, 0.46) * (1 - ease(0.68, 0.82))

        // A key reaches one row up and one down, so neighbors overlap by two rows.
        let step = (2 + rise) * cell
        var lifts: [Double] = [], slides: [Double] = [], turns: [Double] = []
        for k in 0 ..< verses.count {
            lifts.append(Double(k) * step * up)
            let slide = Double.random(in: -rule.slide ... rule.slide, using: &rng).rounded() * cell
            let angle = Double.random(in: -rule.turn ... rule.turn, using: &rng) * turn
            slides.append(slide * swing)
            turns.append(angle * swing)
        }
        return (lifts, slides, turns)
    }

    private static func rule(_ look: Look) -> Rule {
        switch look {
        case .wood:
            return Rule(verses: 5, columns: 15, rowsPerVerse: 6, depth: 6, keys: 1 ... 2, keyWidth: 2 ... 5,
                        windows: 0 ... 2, slide: 2, turn: 0.28,
                        ground: Color(white: 0.62), face: Color(red: 0.46, green: 0.25, blue: 0.16), material: .satin)
        case .stone:
            return Rule(verses: 6, columns: 11, rowsPerVerse: 6, depth: 8, keys: 1 ... 2, keyWidth: 2 ... 4,
                        windows: 1 ... 2, slide: 1, turn: 0.22,
                        ground: Color(white: 0.52), face: Color(red: 0.76, green: 0.62, blue: 0.46), material: .clay)
        case .aluminum:
            return Rule(verses: 9, columns: 24, rowsPerVerse: 4, depth: 3, keys: 1 ... 3, keyWidth: 3 ... 7,
                        windows: 0 ... 0, slide: 3, turn: 0.08,
                        ground: Color(white: 0.9), face: Color(red: 0.74, green: 0.75, blue: 0.77),
                        material: .physicallyBased(metallic: 0.55, roughness: 0.42))
        }
    }
}
