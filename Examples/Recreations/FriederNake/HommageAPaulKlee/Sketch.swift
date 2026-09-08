//  Recreation after Frieder Nake - "13/9/65 Nr. 2" (1965), the plotter drawing
//  usually called "Hommage à Paul Klee": horizontal bands whose edges buckle
//  across the sheet, with vertical lines, triangles, and circles set into them
//  by chance. A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist.
//  http://dada.compart-bremen.de/item/artwork/414
//
//  An original Ollin interpretation written from the work itself and from
//  Nake's own list of the drawing's random decisions (Programm-Information
//  PI-21, quoted in the compArt database). No source was ported: the piece
//  was drawn on a Zuse Graphomat Z64 from a machine-language program for the
//  ER56 that is not the program here.

import Ollin

/// "13/9/65 Nr. 2" (Frieder Nake, 1965): the sheet is cut into horizontal
/// bands of unequal width, and the line between one band and the next bends
/// from vertex to vertex on its way across, never crossing its neighbors. Each
/// band is a row of quadrilaterals, and for every one of them the program
/// rolled a decision: leave it empty, fill it with vertical lines, or set
/// triangles in it. Then it threw a handful of circles over the whole sheet.
/// That is the entire drawing. Nake listed the chance decisions himself: the
/// widths of the bands at the left edge, the buckling of their edges, the
/// choice for each quadrilateral, how many signs it gets and where, and the
/// number, place, and size of the circles.
///
/// He named it after Paul Klee's *Hauptweg und Nebenwege* (1929), for the way
/// that painting sets a rhythm of horizontals against verticals, and it is not
/// a simulation of Klee: the painting has no circles, and its bands run the
/// other way. The drawing is one of the most reproduced images of the first
/// computer art, shown in Stuttgart in November 1965 beside Georg Nees's
/// plates.
///
/// Two things are worth noticing. The picture has two scales at once, a
/// composition of bands you read from across the room and a texture of signs
/// you read up close, and both came out of the same short list of rolls. And
/// the vertical lines are the only thing that varies in *amount*: a dense cell
/// reads as a dark patch, a sparse one as a pale one, so the sheet has tone
/// though every mark is the same black line.
///
/// Try it: `sheetSeed` is the whole piece, and every seed is a different
/// sheet from the same rules. `buckling` is how far the band edges may wander
/// (0 rules them straight), `density` scales how many signs a filled cell
/// gets, and `circles` is how many are thrown. The lines export as strokes, so
/// `--export-svg` gives the plotter drawing back.
@main
final class HommageAPaulKlee: Sketch {
    @Param(4 ... 14, icon: "rectangle.split.3x1") var bands = 8.0
    @Param(0 ... 1, icon: "waveform.path") var buckling = 0.6
    @Param(0 ... 2, icon: "line.3.horizontal") var density = 1.0
    @Param(0 ... 20, icon: "circle") var circles = 9.0
    @Param(1 ... 999, icon: "dice") var sheetSeed = 13.0

    override func draw() {
        background(Color(hex: 0xF4F1EA))
        noFill()
        stroke(.black)
        strokeWeight(1.5)
        randomSeed(Int(sheetSeed.rounded()))

        // The sheet: a square with a margin, like the 50 cm plate.
        let side = min(width, height) * 0.86
        let sheet = Rectangle(center: center, width: side, height: side)

        // 1. The band widths, rolled at the left edge.
        let count = Int(bands.rounded())
        let weights = (0 ..< count).map { _ in random(0.35, 1.65) }
        let total = weights.reduce(0, +)
        var bases: [Double] = [sheet.y]
        for w in weights { bases.append(bases[bases.count - 1] + w / total * side) }

        // 2. The edges buckle from vertex to vertex on the way across, each
        //    kept to a share of the band above and the band below so no two
        //    ever cross. Every edge has its own stations, so the kinks never
        //    line up down the sheet.
        var edges: [[Vector2]] = []
        for i in 0 ... count {
            let stations = Int(random(6, 11))
            let above = i > 0 ? bases[i] - bases[i - 1] : 0
            let below = i < count ? bases[i + 1] - bases[i] : 0
            let up = -0.45 * above * buckling, down = 0.45 * below * buckling
            var points: [Vector2] = []
            for k in 0 ... stations {
                var x = sheet.x + Double(k) / Double(stations) * side
                if k > 0, k < stations { x += random(-0.3, 0.3) * side / Double(stations) }
                let y = bases[i] + (up < down ? random(up, down) : 0)
                points.append(Vector2(x, y))
            }
            edges.append(points)
            drawPolyline(points)
        }

        // 3. Each quadrilateral of a band, cut at its upper edge's stations,
        //    rolls its own decision: empty, vertical lines, or triangles, then
        //    how many and where.
        for i in 0 ..< count {
            let upper = edges[i], lower = edges[i + 1]
            for k in 0 ..< upper.count - 1 {
                let x0 = upper[k].x, x1 = upper[k + 1].x
                let choice = random(0, 1)
                if choice < 0.42 { continue }
                if choice < 0.82 {
                    let lines = Int(random(1, 24) * density)
                    for _ in 0 ..< lines {
                        let x = random(x0, x1)
                        drawLine(Vector2(x, height(of: upper, at: x)),
                                 Vector2(x, height(of: lower, at: x)))
                    }
                } else {
                    let signs = Int(random(1, 6) * density)
                    for _ in 0 ..< signs {
                        let x = random(x0, x1)
                        let top = height(of: upper, at: x), bottom = height(of: lower, at: x)
                        let room = bottom - top
                        let size = random(0.15, 0.5) * room
                        let base = bottom - random(0, room - size)
                        drawTriangle(Vector2(x - size / 2, base), Vector2(x + size / 2, base),
                                     Vector2(x, base - size))
                    }
                }
            }
        }

        // 4. The circles: where, and how big.
        for _ in 0 ..< Int(circles.rounded()) {
            let radius = random(0.012, 0.075) * side
            drawCircle(random(sheet.x + radius, sheet.x + side - radius),
                       random(sheet.y + radius, sheet.y + side - radius), radius)
        }
    }

    /// Where a buckled edge sits at `x`, read off its vertices.
    private func height(of edge: [Vector2], at x: Double) -> Double {
        guard let first = edge.first, let last = edge.last else { return 0 }
        if x <= first.x { return first.y }
        for k in 1 ..< edge.count where x <= edge[k].x {
            let a = edge[k - 1], b = edge[k]
            let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 0
            return a.y + (b.y - a.y) * t
        }
        return last.y
    }
}
