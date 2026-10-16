//  Recreation after Dóra Maurer - the Displacements of 1972 to 1976, read from
//  Displacements, Step 18 with Two Random-Quasi-Images (1976, acrylic, canvas,
//  wood, 200 x 160 cm), promised to Tate in 2019, and Displacements 1-6 (1976,
//  gouache and black ink over graphite on six sheets, each 60.9 x 49.8 cm) in
//  The Metropolitan Museum of Art. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or her estate.
//  https://www.tate.org.uk/art/artworks/maurer-displacements-step-18-with-two-random-quasi-images-t15451
//  https://www.metmuseum.org/art/collection/search/810832
//
//  An original Ollin interpretation, written from the paintings and from the
//  system as she stated it, quoted in László Beke's essay "Objective
//  Tenderness" (1994): a surface of 4:5 divided into 10 x 10 units, two
//  congruent planes each divided into four parts of equal territory, the parts
//  displaced one grid unit a step, the cold ones diagonally and the warm ones
//  vertically and horizontally. Nothing was ported. The paths the parts take
//  between the corners, the looks, and the motion are this sketch's own.

import Foundation
import Ollin

/// Displacements (Dóra Maurer, Budapest and Vienna, from 1972). Maurer set
/// herself a scene and a rule, and painted what the rule did. The scene, in
/// her words: a rectangular surface with sides in the proportion 4:5, divided
/// into 10 by 10 units by a grid, and lying on it two congruent planes, the
/// upper one marked with diagonal lines in warm colors and the lower one in
/// cold colors, each divided into four parts of equal territory. The parts are
/// what moves. Each step displaces every part by one unit of the grid, the
/// cold parts diagonally and the warm ones vertically and horizontally, and
/// the eight of them, red, orange, yellow, and brown over green, blue, violet,
/// and turquoise, come to overlap in more and more complex ways. The canvases
/// are the system at one step, ruled in thin colored lines on raw canvas, and
/// on some of them a few cells chosen by random numbers are painted in full,
/// every line widened into a band of flat color: those windows are the first
/// quasi-images, details of the system enlarged until they stop representing
/// anything.
///
/// This sketch keeps the scene and the rule. The four parts of each plane are
/// its quarters, 5 by 5 units, and at step 0 a warm part and a cold one lie
/// together in each corner as a contrasting pair (red and green, orange and
/// blue, yellow and violet, brown and turquoise). Every part is ruled with
/// one diagonal a cell, from the lower left corner to the upper right, and
/// keeps a lane of its own a little off the grid, so lines that coincide run
/// side by side as a bundle instead of hiding one another. Each step moves a
/// warm part one unit along the border toward the next corner and a cold part
/// one unit along the diagonal toward the opposite one, so after five steps
/// every part rests in a corner again: the warm ones a quarter turn around
/// and the cold ones across. Twenty steps bring them all home. The seed deals
/// which pair starts in which corner, which way the warm parts turn, and the
/// windows, and a press deals the next. `look` picks the raw canvas with
/// `windows` painted cells or the gouache sheet on white paper; `seconds` is
/// the length of a step, which rests on the grid and then glides to the next.
///
/// `--export-svg` gives every part back as a rectangle and its diagonals as
/// lines at their own two ends, so the rule can be read from the file: each
/// part 5 by 5 units on the grid apart from its lane, at the place the rule
/// gives for the step, one unit from where it was a step before, and every
/// band in a window on a line of the system.
@main
final class Displacements: Sketch {
    /// The ground and the line, after the two kinds of work.
    enum Look: String, CaseIterable, ParamOption {
        /// 1976: the system ruled on raw canvas, with cells painted in full.
        case canvas
        /// 1976: the gouache sheets, the system on white paper.
        case paper
    }

    @Param(icon: "paintpalette") var look = Look.canvas
    @Param(0 ... 4, icon: "square.dashed") var windows = 2
    @Param(0.3 ... 4, icon: "clock") var seconds = 1.0

    override var canvasSize: CanvasSize { .size(864, 1080) }
    override var loopDuration: Double? { Double(System.period) * seconds }

    /// The scene and the rule.
    struct System {
        /// The grid is `units` by `units`; a part is `side` by `side`.
        static let units = 10
        static let side = 5
        /// The steps that bring every part home.
        static let period = 20
        /// The corners' origins in units, clockwise from the top left.
        static let corners = [Vector2(0, 0), Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]

        struct Part {
            var corner: Int
            var isWarm: Bool
            var color: Color
            /// The part's own offset off the grid, in lanes, from -3.5 to 3.5.
            var lane: Double
        }

        var parts: [Part] = []
        /// 1 sends the warm parts clockwise around the border, -1 the other way.
        var turn = 1

        /// The top left corner of a part after `step` steps, in units. A whole
        /// step lands on the grid; a fraction lies on the way to the next.
        func origin(of part: Part, at step: Double) -> Vector2 {
            let corners = Self.corners
            if part.isWarm {
                // Along the border, one corner each five steps.
                let s = Self.wrapped(step, Double(Self.period))
                let leg = min(3, Int(s / Double(Self.side)))
                let from = corners[(part.corner + turn * leg + 8) % 4]
                let to = corners[(part.corner + turn * (leg + 1) + 8) % 4]
                return from + (to - from) * ((s - Double(leg * Self.side)) / Double(Self.side))
            }
            // Along the diagonal to the opposite corner and back.
            let s = Self.wrapped(step, Double(2 * Self.side))
            let across = s <= Double(Self.side) ? s : Double(2 * Self.side) - s
            let from = corners[part.corner], to = corners[(part.corner + 2) % 4]
            return from + (to - from) * (across / Double(Self.side))
        }

        /// The diagonals of a part at `origin`: one through each cell from its
        /// lower left corner to its upper right, nine lines from edge to edge.
        static func diagonals(from origin: Vector2) -> [(Vector2, Vector2)] {
            let n = Double(side)
            return (1 ..< 2 * side).map { m in
                let m = Double(m)
                return m <= n
                    ? (origin + Vector2(0, m), origin + Vector2(m, 0))
                    : (origin + Vector2(m - n, n), origin + Vector2(n, m - n))
            }
        }

        static func wrapped(_ value: Double, _ period: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: period)
            return r < 0 ? r + period : r
        }
    }

    /// The contrasting pairs, warm first, after the colors of the 1976 canvas
    /// and sheets.
    static let pairs: [(warm: Color, cold: Color)] = [
        (Color(hex: 0xD9281C), Color(hex: 0x1D8A48)),   // red, green
        (Color(hex: 0xEE7B1E), Color(hex: 0x1E5FD8)),   // orange, blue
        (Color(hex: 0xF0BE14), Color(hex: 0x5B3A9A)),   // yellow, violet
        (Color(hex: 0x6E4B26), Color(hex: 0x169BA8)),   // brown, turquoise
    ]

    private struct Dealt: Equatable { var seed: Int; var windows: Int }
    private var dealtFor: Dealt?
    private var system = System()
    /// The painted windows, in cells: a corner and a size.
    private var painted: [(column: Int, row: Int, columns: Int, rows: Int)] = []
    private var pressed = false

    /// The grid's top left corner and one cell, in pixels.
    private var gridOrigin: Vector2 { Vector2(width * 0.06, height * 0.06) }
    private var cell: Vector2 { Vector2(width * 0.88 / 10, height * 0.88 / 10) }

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(seed: variation, windows: windows)
        if dealtFor != wanted {
            dealtFor = wanted
            deal()
        }

        // A step rests on the grid for its first part, then glides to the next.
        let raw = time / max(0.1, seconds)
        let whole = (raw + 1e-9).rounded(.down)
        let rest = 0.4
        let glide = max(0, min(1, (raw - whole - rest) / (1 - rest)))
        let step = whole + glide * glide * (3 - 2 * glide)
        let shown = Int(System.wrapped(whole, Double(System.period)))

        let onCanvas = look == .canvas
        background(onCanvas ? Color(hex: 0xD8CCAA) : Color(hex: 0xF6F4EE))
        noFill()
        strokeCap(.butt)
        strokeJoin(.miter)

        // The grid.
        let g = gridOrigin, c = cell
        stroke(Color(hex: 0x1A1A1A).withAlpha(onCanvas ? 0.8 : 0.9))
        strokeWeight(onCanvas ? 0.9 : 1.1)
        for i in 0 ... System.units {
            let x = g.x + Double(i) * c.x, y = g.y + Double(i) * c.y
            drawLine(x, g.y, x, g.y + 10 * c.y)
            drawLine(g.x, y, g.x + 10 * c.x, y)
        }

        // The parts, the lower plane first, each in its lane.
        let lane = c.x / 44
        let lineWeight = onCanvas ? 1.15 : 1.6
        for part in drawingOrder() {
            let origin = system.origin(of: part, at: step)
            let offset = Vector2(part.lane * lane, part.lane * lane)
            stroke(part.color)
            strokeWeight(lineWeight)
            drawRect(corner: pixel(origin) + offset, width: 5 * c.x, height: 5 * c.y)
            for (a, b) in System.diagonals(from: origin) {
                drawLine(pixel(a) + offset, pixel(b) + offset)
            }
        }

        // The windows: cells painted in full, every line widened into a band.
        if onCanvas {
            for window in painted {
                paint(window, at: step)
            }
            drawText("Displacements, step \(shown)", g.x, height * 0.028,
                     size: height * 0.0135, color: Color(hex: 0x3A3630).withAlpha(0.85), align: .left, .middle)
        }
    }

    /// One window: white ground, and each part's lines as bands of its color,
    /// the warm plane over the cold one, each band in the part's lane.
    private func paint(_ window: (column: Int, row: Int, columns: Int, rows: Int), at step: Double) {
        let c = cell
        let corner = pixel(Vector2(Double(window.column), Double(window.row)))
        let frame = Rectangle(x: corner.x, y: corner.y,
                              width: Double(window.columns) * c.x, height: Double(window.rows) * c.y)
        // A band is a tenth of a cell; a diagonal band is widened so that
        // neighboring lanes touch across it as they do along the edges.
        let band = c.x / 10
        let diagonal = band * (c.x + c.y) / (c.x * c.x + c.y * c.y).squareRoot()
        withClip(frame) {
            noStroke()
            fill(Color(hex: 0xF4F2EA))
            drawRect(corner: corner, width: frame.width, height: frame.height)
            noFill()
            for part in drawingOrder() {
                let origin = system.origin(of: part, at: step)
                let offset = Vector2(part.lane * band, part.lane * band)
                let topLeft = pixel(origin) + offset
                let reach = Rectangle(x: topLeft.x - band / 2, y: topLeft.y - band / 2,
                                      width: 5 * c.x + band, height: 5 * c.y + band)
                stroke(part.color)
                withClip(reach) {
                    strokeWeight(diagonal)
                    for (a, b) in System.diagonals(from: origin) {
                        let p = pixel(a) + offset, q = pixel(b) + offset
                        let along = (q - p).normalized * band
                        drawLine(p - along, q + along)
                    }
                }
                // A polygon, so the corners are mitered square as painted.
                strokeWeight(band)
                drawPolygon([topLeft, topLeft + Vector2(5 * c.x, 0),
                             topLeft + Vector2(5 * c.x, 5 * c.y), topLeft + Vector2(0, 5 * c.y)])
            }
        }
    }

    /// The lower plane first, then the upper one, each by lane.
    private func drawingOrder() -> [System.Part] {
        system.parts.filter { !$0.isWarm }.sorted { $0.lane < $1.lane }
            + system.parts.filter { $0.isWarm }.sorted { $0.lane < $1.lane }
    }

    private func pixel(_ unit: Vector2) -> Vector2 {
        gridOrigin + Vector2(unit.x * cell.x, unit.y * cell.y)
    }

    /// Deals the corners, the turn, and the windows from the seed.
    private func deal() {
        randomSeed(variation)
        // Pair p keeps lanes 2p and 2p + 1, so a contrasting pair lies side by
        // side; the seed deals the corner each pair starts in.
        let corners = shuffled([0, 1, 2, 3])
        system.parts = []
        for (p, pair) in Self.pairs.enumerated() {
            system.parts.append(.init(corner: corners[p], isWarm: true, color: pair.warm,
                                      lane: Double(2 * p) - 3.5))
            system.parts.append(.init(corner: corners[p], isWarm: false, color: pair.cold,
                                      lane: Double(2 * p + 1) - 3.5))
        }
        system.turn = random() < 0.5 ? 1 : -1

        // Windows of one or two columns by two or three rows, chosen by random
        // numbers and kept apart.
        painted = []
        var tries = 0
        while painted.count < windows && tries < 200 {
            tries += 1
            let columns = randomChoice([1, 2]), rows = randomChoice([2, 3])
            let column = randomChoice(Array(0 ... System.units - columns))
            let row = randomChoice(Array(0 ... System.units - rows))
            let clear = painted.allSatisfy { other in
                column + columns < other.column || other.column + other.columns < column
                    || row + rows < other.row || other.row + other.rows < row
            }
            if clear { painted.append((column, row, columns, rows)) }
        }
    }
}
