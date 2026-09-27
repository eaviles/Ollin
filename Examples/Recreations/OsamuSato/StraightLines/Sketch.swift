//  Recreation after Osamu Sato - "The Art of Computer Designing: A Black and
//  White Approach" (1993, Graphic-Sha), Chapter 1, "Straight Lines", read from
//  the scan of the book on the Internet Archive: the chapter's hints page (the
//  two relations of lines, and the operations a computer does easily), and
//  Step 3, Lesson 2, page 22, the eye framed by the word EYE set in hatched
//  letters, captioned "An eyeball, created with nothing but straight lines."
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist.
//  https://archive.org/details/satoArtOfComputerDesigning
//
//  An original Ollin interpretation written from the printed pages. The
//  letterforms, the eye's parts and their counts are our own. Nothing was
//  ported: the book shipped a disk of its designs, and none of it was used.

import Foundation
import Ollin

/// "An eyeball, created with nothing but straight lines" (Osamu Sato, *The
/// Art of Computer Designing*, 1993, Chapter 1). The chapter opens with two
/// relations, "parallel lines that never meet, diagonals that inevitably
/// do", and a short list of what a computer does easily: enlarge and shrink,
/// copy, repeat, divide and combine, mirror, and rotate. Its page 22 builds
/// an eye from nothing else. The Japanese caption says it more plainly: even
/// an eyeball was really born from a single straight line.
///
/// This sketch builds that page. Every mark is one straight line. The pupil
/// is twelve lines crossing at one point. Each lid is one bent line of three
/// strokes copied five times, each copy shifted up from the last, so the
/// strokes cross where the copies overlap. Blocks of parallel lines stand
/// around the eye on an ellipse, one block per sixteenth of a turn, each
/// block's lines along the ellipse. Outside them, thirty-two spikes are fans
/// of five lines meeting at a point. A star at the top and bottom and two
/// arrowheads at each side are fans too. Around the eye, the word is set in
/// hatched letters, where each filled cell of a letter is three short
/// horizontals, as many times as fits around the eye.
///
/// Every angle in the design is a whole multiple of 3.75 degrees, one
/// forty-eighth of a half turn, and the eye is mirrored left to right and top
/// to bottom. The motion keeps both rules: the pupil turns a click at a time,
/// the lids blink by folding their copies back into one line, and the spikes
/// breathe along their own axes. Once a `cycle`, the page is taken apart line
/// by line, down to one line through the pupil, and built again: first the
/// pupil, then the lids, the blocks, the spikes, the stars, and last the
/// letters. `word` is what the letters spell, `breath` how far the spikes
/// reach, and `cycle` how long one build lasts.
///
/// Every line exports as a line, so `--export-svg` gives the page back as
/// nothing but straight segments.
@main
final class StraightLines: Sketch {
    @Param(icon: "textformat") var word = "EYE"
    @Param(0 ... 1, icon: "sun.max") var breath = 0.5
    @Param(12 ... 90, icon: "clock") var cycle = 32.0

    override var canvasSize: CanvasSize { .size(1000, 1400) }
    override var loopDuration: Double? { max(12, cycle) }

    private let paper = Color(white: 0.955)
    private let ink = Color(white: 0.08)

    /// One straight line, in page units, with the moment of the build it
    /// appears at (0 is the first line, 1 the last).
    private struct Segment {
        var a: Vector2
        var b: Vector2
        var birth: Double
    }

    /// The step every angle is a multiple of: 3.75 degrees.
    private let step = Double.pi / 48

    // The eye's parts, in page units about the eye's center.
    private let lidCorner = 150.0       // half the eye's width
    private let lidTop = 45.0           // half the width of each lid's flat top
    private let lidCopies = 5
    private let lidGap = 11.0           // the shift between two copies of a lid
    private let pupilRadius = 32.0
    private let ringA = 248.0           // the ellipse the blocks stand on
    private let ringB = 190.0
    private let blockLines = 6
    private let blockPitch = 8.0
    private let spikeBase = 30.0        // the spikes' base, outside the blocks
    private let starRadius = 46.0
    private let arrowLength = 44.0
    /// The four spikes on the axes at their farthest reach.
    private let farthest = 118.0 * 1.12

    override func setup() {
        noFill()
        strokeCap(.butt)
    }

    override func draw() {
        background(paper)
        let k = width / 1000
        let center = Vector2(500, 700)
        let segments = placed(figure(at: time), at: center) + lettering(around: center)
        let reveal = revealed(at: time)

        stroke(ink)
        strokeWeight(1.3 * k)
        for s in segments where s.birth <= reveal {
            drawLine(s.a * k, s.b * k)
        }
    }

    // MARK: The build

    /// How much of the page stands at time `t`: all of it for most of the
    /// cycle, then taken apart down to the first line, held there, and built
    /// again.
    private func revealed(at t: Double) -> Double {
        let length = max(12, cycle)
        let u = (t / length).truncatingRemainder(dividingBy: 1)
        switch u {
        case ..<0.55: return 1
        case ..<0.70: return 1 - (u - 0.55) / 0.15
        case ..<0.76: return 0
        default: return (u - 0.76) / 0.24
        }
    }

    // MARK: The eye

    /// The eye is drawn at nine tenths of the units below, about the page's
    /// center. A uniform scale leaves every angle as it was.
    private let figureScale = 0.9

    private func placed(_ segments: [Segment], at center: Vector2) -> [Segment] {
        segments.map { Segment(a: center + $0.a * figureScale, b: center + $0.b * figureScale, birth: $0.birth) }
    }

    /// Every line of the eye at time `t`, about the eye's center. With
    /// `envelope`, every spike at its farthest reach, the room the eye can
    /// ever take.
    private func figure(at t: Double, envelope: Bool = false) -> [Segment] {
        var out: [Segment] = []
        func add(_ a: Vector2, _ b: Vector2, _ birth: Double) {
            out.append(Segment(a: a, b: b, birth: birth))
        }
        /// A unit vector at `n` steps from the +x axis (y points down the page).
        func dir(_ n: Double) -> Vector2 { Vector2(cos(n * step), sin(n * step)) }

        // The pupil: twelve lines through one point, turning a click (two
        // steps) every beat while the page stands whole. Mirrored twins are
        // born together, the horizontal first: the one line the page comes
        // back to, which is why the pupil rests square while it is built.
        let click = revealed(at: t) < 1 ? 0 : 2 * floor(t / 1.1)
        for i in 0 ..< 12 {
            let n = Double(4 * i) + click
            let d = dir(n)
            var folded = (n * step).truncatingRemainder(dividingBy: .pi)
            if folded > .pi / 2 { folded = .pi - folded }
            add(d * -pupilRadius, d * pupilRadius, 0.06 * folded / (.pi / 2))
        }

        // The lids: one bent line of three strokes, copied and shifted. A
        // blink folds the copies back onto the first.
        let blinkPhase = (t / 5.3).truncatingRemainder(dividingBy: 1)
        let fold = blinkPhase > 0.93 ? sin((blinkPhase - 0.93) / 0.07 * .pi) : 0
        let shift = lidGap * (1 - 0.92 * fold)
        let rise = (lidCorner - lidTop) * tan(6 * step)   // 22.5 degrees
        let over = 9.0
        for j in 0 ..< lidCopies {
            let lift = Double(j) * shift
            let birth = 0.06 + 0.06 * Double(j) / Double(lidCopies - 1)
            let corner = Vector2(-lidCorner, 0), joint = Vector2(-lidTop, -rise)
            let u = (joint - corner).normalized
            // The upper lid, then its mirror below the eye.
            for below in [1.0, -1.0] {
                func m(_ p: Vector2) -> Vector2 { Vector2(p.x, (p.y - lift) * below) }
                func mx(_ p: Vector2) -> Vector2 { Vector2(-p.x, p.y) }
                add(m(corner - u * over), m(joint + u * over), birth)
                add(m(mx(corner - u * over)), m(mx(joint + u * over)), birth)
                add(m(Vector2(-lidTop - over, -rise)), m(Vector2(lidTop + over, -rise)), birth)
            }
        }

        // At each corner of the eye, outside it: a wedge of verticals that
        // shrink toward the eye, then a block of equal ones.
        for side in [-1.0, 1.0] {
            for i in 0 ..< 6 {
                let x = side * (lidCorner + 16 + Double(i) * 8)
                let half = 8 + Double(i) * 6
                add(Vector2(x, -half), Vector2(x, half), 0.12 + 0.02 * Double(i) / 5)
            }
        }

        // Above and below the lids: a band of diagonals at 45 degrees, one
        // family from each side reaching past the middle, so the two cross
        // there, and past the band a block of verticals.
        let lidRoof = rise + Double(lidCopies - 1) * lidGap
        for vertical in [-1.0, 1.0] {
            let near = vertical * (lidRoof + 16), far = vertical * (lidRoof + 36)
            for i in 0 ..< 17 {
                let x = -122.0 + Double(i) * 10
                let birth = 0.14 + 0.03 * Double(i) / 16
                // Each line's end away from the eye leans out toward its side.
                add(Vector2(x + 20, near), Vector2(x, far), birth)
                add(Vector2(-x - 20, near), Vector2(-x, far), birth)
            }
            for i in 0 ..< 10 {
                let x = -45.0 + Double(i) * 10
                let yA = vertical * (lidRoof + 44), yB = vertical * (lidRoof + 72)
                add(Vector2(x, yA), Vector2(x, yB), 0.18 + 0.02 * abs(x) / 45)
            }
        }

        // The ring: sixteen blocks on an ellipse, one per sixteenth of a turn
        // of the tangent, each block's lines along the ellipse and stacked out
        // from it, the outer ones longer. Copies appear from the sides of the
        // eye toward its top and bottom.
        for j in 0 ..< 16 {
            let tangent = Double(6 * j)
            let (p, normal) = ellipsePoint(tangentSteps: tangent, a: ringA, b: ringB)
            let along = dir(tangent)
            let reach = abs(normal.y)
            for i in 0 ..< blockLines {
                let offset = (Double(i) - Double(blockLines - 1) / 2) * blockPitch
                let half = 19 + Double(i) * 2.4
                let mid = p + normal * offset
                add(mid - along * half, mid + along * half, 0.22 + 0.1 * reach + 0.015 * Double(i))
            }
        }

        // The spikes: thirty-two fans of five lines meeting at a point, one on
        // each block and one between each pair, their bases on an ellipse
        // outside the blocks. Each line runs from the point back to the base.
        // The four at the ends of the axes reach farther, and all of them
        // breathe along their axes.
        let outerA = ringA + spikeBase, outerB = ringB + spikeBase
        for q in 0 ..< 32 {
            let normalSteps = Double(3 * q)
            let axis = dir(normalSteps)
            let (base, _) = ellipsePoint(normalSteps: normalSteps, a: outerA, b: outerB)
            var length = q % 2 == 0 ? 96.0 : 76.0
            if q % 8 == 0 { length = 118 }
            let wave = envelope ? 1 : sin(t * 1.6 - 2.5 * abs(axis.y))
            length *= 1 + 0.12 * (envelope ? 1 : breath) * wave
            let apex = base + axis * length
            let reach = abs(axis.y)
            for r in -2 ... 2 {
                let back = dir(normalSteps + 48 + Double(r))
                let run = length / cos(Double(r) * step)
                add(apex, apex + back * run, 0.34 + 0.12 * reach + 0.01 * Double(abs(r)))
            }
        }

        // The stars at the top and bottom: twelve fans of three lines, each
        // from its point in to a circle, and the twelve-pointed star polygon
        // that joins every fifth corner of that circle.
        let starDistance = outerB + farthest + 10 + starRadius
        for vertical in [-1.0, 1.0] {
            let sc = Vector2(0, vertical * starDistance)
            let inner = starRadius * 0.42
            for i in 0 ..< 12 {
                let n = Double(8 * i) - 24        // the first point straight up
                let point = sc + dir(n) * starRadius
                for r in -1 ... 1 {
                    let back = dir(n + 48 + Double(2 * r))
                    let run = (starRadius - inner) / cos(Double(2 * r) * step)
                    add(point, point + back * run, 0.50 + 0.01 * Double(abs(r)))
                }
                let from = sc + dir(n) * inner, to = sc + dir(n + 40) * inner
                add(from, to, 0.54)
            }
        }

        // The arrowheads at each side: two fans of five lines each, pointing
        // out from the eye.
        for side in [-1.0, 1.0] {
            for i in 0 ..< 2 {
                let base = outerA + farthest + 10 + Double(i) * (arrowLength + 10)
                let apex = Vector2(side * (base + arrowLength), 0)
                for r in -2 ... 2 {
                    let open = dir((side < 0 ? 0 : 48) + Double(2 * r))
                    let run = arrowLength / cos(Double(2 * r) * step)
                    add(apex, apex + open * run, 0.56 + 0.02 * Double(i) + 0.005 * Double(abs(r)))
                }
            }
        }
        return out
    }

    /// The point of the ellipse `a` by `b` whose tangent points `tangentSteps`
    /// steps from +x (counterclockwise on the page), and its outward normal.
    private func ellipsePoint(tangentSteps: Double, a: Double, b: Double) -> (Vector2, Vector2) {
        let phi = tangentSteps * step
        let t = atan2(-cos(phi) / a, sin(phi) / b)
        let p = Vector2(a * cos(t), b * sin(t))
        let normal = Vector2(cos(t) / a, sin(t) / b).normalized
        return (p, normal)
    }

    /// The point of the ellipse `a` by `b` whose outward normal points
    /// `normalSteps` steps from +x, and that normal.
    private func ellipsePoint(normalSteps: Double, a: Double, b: Double) -> (Vector2, Vector2) {
        let psi = normalSteps * step
        let t = atan2(b * sin(psi), a * cos(psi))
        return (Vector2(a * cos(t), b * sin(t)), Vector2(cos(psi), sin(psi)))
    }

    // MARK: The letters

    /// The hatched letters: five rows, and each filled cell three short
    /// horizontals. A letter is as wide as its strokes need, from one cell
    /// (I) to five (M, W).
    private static let glyphs: [Character: [String]] = [
        "A": ["###", "#.#", "###", "#.#", "#.#"],
        "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": ["###", "#..", "#..", "#..", "###"],
        "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["##", "#.", "##", "#.", "##"],
        "F": ["##", "#.", "##", "#.", "#."],
        "G": ["###", "#..", "#.#", "#.#", "###"],
        "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["#", "#", "#", "#", "#"],
        "J": ["..#", "..#", "..#", "#.#", "###"],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
        "L": ["#.", "#.", "#.", "#.", "##"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
        "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
        "O": ["###", "#.#", "#.#", "#.#", "###"],
        "P": ["###", "#.#", "###", "#..", "#.."],
        "Q": ["###", "#.#", "#.#", "###", "..#"],
        "R": ["###", "#.#", "##.", "#.#", "#.#"],
        "S": ["###", "#..", "###", "..#", "###"],
        "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"],
        "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
        "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", "###", ".#.", ".#."],
        "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#", "##", ".#", ".#", ".#"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", ".##", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
        " ": [".", ".", ".", ".", "."],
    ]

    private let cellWidth = 30.0
    private let cellGutter = 6.0
    private let letterGap = 14.0
    private let linePitch = 6.5
    private let wordGap = 56.0
    private let margin = 60.0

    /// The word's letters in order, unknown characters left out.
    private var letters: [[String]] {
        word.uppercased().compactMap { Self.glyphs[$0] }
    }

    private func wordWidth(_ letters: [[String]]) -> Double {
        let cells = letters.reduce(0) { $0 + $1[0].count }
        return Double(cells) * cellWidth - cellGutter + Double(max(0, letters.count - 1)) * letterGap
    }

    /// The word set in every slot of every row that clears the eye: three
    /// rows above it and three below, the slots of a row centered on the page.
    private func lettering(around center: Vector2) -> [Segment] {
        let letters = self.letters
        guard !letters.isEmpty else { return [] }
        let w = wordWidth(letters)
        let h = 15 * linePitch
        let perRow = max(1, Int((1000 - 2 * margin + wordGap) / (w + wordGap)))
        let rowWidth = Double(perRow) * w + Double(perRow - 1) * wordGap
        let rowTops = [70.0, 228, 386]
        let eye = placed(figure(at: 0, envelope: true), at: center)
        var out: [Segment] = []
        for (rank, top) in rowTops.reversed().enumerated() {
            for flipped in [false, true] {
                let y = flipped ? 1400 - top - h : top
                for slot in 0 ..< perRow {
                    let x = (1000 - rowWidth) / 2 + Double(slot) * (w + wordGap)
                    let box = Rectangle(x: x, y: y, width: w, height: h)
                    guard clears(box, of: eye) else { continue }
                    out += set(letters, at: Vector2(x, y), rank: rank)
                }
            }
        }
        return out
    }

    /// Whether a word's box, with room to spare, stays clear of every line
    /// the eye can ever reach.
    private func clears(_ box: Rectangle, of eye: [Segment]) -> Bool {
        let room = 24.0
        let x0 = box.x - room, x1 = box.x + box.width + room
        let y0 = box.y - room, y1 = box.y + box.height + room
        for s in eye {
            // Clip the line to the box (Liang and Barsky); any part left inside is a clash.
            var lo = 0.0, hi = 1.0
            let d = s.b - s.a
            let checks = [(-d.x, s.a.x - x0), (d.x, x1 - s.a.x), (-d.y, s.a.y - y0), (d.y, y1 - s.a.y)]
            var inside = true
            for (p, q) in checks {
                if p == 0 {
                    if q < 0 { inside = false; break }
                } else {
                    let r = q / p
                    if p < 0 { lo = max(lo, r) } else { hi = min(hi, r) }
                    if lo > hi { inside = false; break }
                }
            }
            if inside { return false }
        }
        return true
    }

    /// One word's lines, its top left at `origin`. Every filled cell is three
    /// horizontals; the rows nearest the eye are set first, and within a word
    /// the lines come in from the top.
    private func set(_ letters: [[String]], at origin: Vector2, rank: Int) -> [Segment] {
        var out: [Segment] = []
        var x = origin.x
        for glyph in letters {
            for (row, cells) in glyph.enumerated() {
                for (column, cell) in cells.enumerated() where cell == "#" {
                    let left = x + Double(column) * cellWidth
                    for i in 0 ..< 3 {
                        let line = row * 3 + i
                        let y = origin.y + (Double(line) + 0.5) * linePitch
                        let birth = 0.62 + 0.38 * (Double(rank) + Double(line) / 15) / 3
                        out.append(Segment(a: Vector2(left, y), b: Vector2(left + cellWidth - cellGutter, y),
                                           birth: birth))
                    }
                }
            }
            x += Double(glyph[0].count) * cellWidth + letterGap
        }
        return out
    }
}
