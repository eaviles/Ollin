//  Recreation after Nasreen Mohamedi - the untitled ink and graphite drawings
//  of the 1970s, read from the square sheets Talwar Gallery shows (Untitled,
//  ca. 1970s, ink and graphite on paper, 7 1/2 x 7 1/2 in.; TG 1640, TG 1633,
//  TG 1638 and TG 1627) and the two the Metropolitan Museum of Art holds
//  (Untitled, ca. 1970, 18 3/4 x 18 3/4 in.; Untitled, ca. 1970, 20 11/16 x
//  20 7/8 in.). Every work of hers is untitled, so nothing here is named after
//  one. A homage, not a reproduction, and not affiliated with or endorsed by
//  the artist or her estate.
//  https://www.talwargallery.com/artists/nasreen-mohamedi
//  https://www.metmuseum.org/exhibitions/listings/2016/nasreen-mohamedi
//
//  An original Ollin interpretation, written from the drawings and from what
//  is known of how she made them. Nothing was ported: the work is a ruling
//  pen and a pencil on paper, on a drafting table.

import Foundation
import Ollin

/// The ruled sheets of the 1970s (Nasreen Mohamedi, Baroda). She drew on
/// small square sheets with the instruments of an architect's office, a
/// ruling pen and a fine technical pen for the ink, a hard pencil for the
/// graphite, the inks often watered down to a grey. A sheet is a stack of
/// horizontals from edge to edge, and what changes across it is only the
/// interval and the weight. The lines gather toward one line, which is drawn
/// heavy, and open out from it, so a field of nothing but parallels reads as
/// planes seen edge on, receding or tilting. Some sheets double the
/// horizontals in one quadrant. Some send a few verticals up through them.
/// Faint pencil verticals at an even pitch cross the whole sheet under the
/// ink, the guides she ruled first. She wrote in her diary of getting "the
/// maximum of the minimum", and the sheets are that sentence drawn.
///
/// This sketch keeps the rule and deals the numbers. The field is cut into
/// registers by heavy lines, one at every boundary, top and bottom included.
/// Each register holds a run of fine lines whose intervals are a geometric
/// progression: the first interval is the smallest and every next one is the
/// last times a ratio, so the lines gather against one heavy line and open
/// toward the other. Which heavy line a register gathers against, how many
/// lines it holds, and its ratio are dealt from the seed, and the weight of
/// a line follows its interval, heavier where the lines are close. In the
/// upper half of the sheet every fine line is doubled on the right, a twin a
/// fraction of the register's smallest interval below it, from the middle
/// out to the edge. A few verticals rise from the bottom edge in graphite,
/// and the pencil guides stand under everything.
///
/// The sheet breathes: over one cycle every register's ratio drifts up and
/// down about the value it was dealt, so the lines tighten and relax while
/// the heavy lines hold still. `breathing` is how far they drift (0 holds the
/// sheet), `seconds` is the cycle and the export loop, `registers` how many
/// bands cut the field, `doubled` the twins in the upper right, `risers` how
/// many verticals rise, and `guides` the pencil grid. The seed is the sheet.
///
/// Every line exports as a line, so `--export-svg` gives the plotter drawing
/// back: the horizontals all at exactly one angle, the intervals in their
/// progressions, and nothing past the margin.
@main
final class Registers: Sketch {
    @Param(3 ... 12, icon: "rectangle.split.3x1") var registers = 7
    @Param(0 ... 1, icon: "arrow.up.and.down") var breathing = 0.5
    @Param(6 ... 60, icon: "clock") var seconds = 24.0
    @Param(icon: "square.on.square") var doubled = true
    @Param(0 ... 12, icon: "arrow.up") var risers = 5
    @Param(icon: "grid") var guides = true

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { max(4, seconds) }

    /// The paper's margin: no ink crosses it.
    private let margin = 60.0
    /// The heavy line at every register boundary, in canvas pixels.
    private let heavyWeight = 2.6
    /// A twin sits this fraction of its register's smallest interval below its line.
    private let twinFraction = 0.5

    /// No two fine lines come closer than this, so every line stays a line.
    private let closest = 3.0

    private let paper = Color(hex: 0xE8E1CD)
    private let ink = Color(white: 0.14)
    private let graphite = Color(white: 0.40)
    private let pencil = Color(white: 0.50)
    private let guide = Color(white: 0.76)

    /// One band between two heavy lines.
    private struct Register {
        var height: Double
        var lines: Int
        /// Every interval is the last times this; dealt above 1.
        var ratio: Double
        /// Where in the cycle this register's breathing starts.
        var phase: Double
        /// Gathers against its bottom line rather than its top one.
        var flipped: Bool
    }

    override func draw() {
        background(paper)
        noFill()
        strokeCap(.butt)
        randomSeed(variation)

        // The field is where a line's center may go; the heaviest line's half
        // width keeps every stroke inside the margin.
        let x0 = margin + heavyWeight / 2, x1 = width - margin - heavyWeight / 2
        let y0 = margin + heavyWeight / 2, y1 = height - margin - heavyWeight / 2
        let fieldHeight = y1 - y0, midX = (x0 + x1) / 2, midY = (y0 + y1) / 2
        let cycle = max(4, seconds)
        let phase = (time / cycle).truncatingRemainder(dividingBy: 1) * 2 * .pi

        // 1. Deal the sheet: the registers, the risers, the pitch of the guides.
        var weights: [Double] = []
        for _ in 0 ..< registers { weights.append(random(0.5, 1.6)) }
        let total = weights.reduce(0, +)
        var dealt: [Register] = []
        for w in weights {
            let height = w / total * fieldHeight
            let ratio = random(1.06, 1.22)
            // The smallest interval a register can hold at its fullest breath
            // still keeps its lines apart: n + 1 intervals from `closest` up
            // by the ratio must fit the height.
            let fullest = pow(ratio, 1 + 0.6 * breathing)
            let room = Int(log(1 + height * (fullest - 1) / closest) / log(fullest)) - 1
            dealt.append(Register(height: height,
                                  lines: max(3, min(Int(random(9, 26)), room)),
                                  ratio: ratio,
                                  phase: random(0, 2 * .pi),
                                  flipped: random(1) < 0.3))
        }
        var risersDealt: [(x: Double, height: Double)] = []
        for _ in 0 ..< risers {
            risersDealt.append((random(x0 + 24, x1 - 24), random(0.2, 0.8) * fieldHeight))
        }
        let guideColumns = Int(random(9, 16))

        // 2. The pencil guides, ruled first and under everything.
        if guides {
            stroke(guide)
            strokeWeight(0.45)
            let pitch = (x1 - x0) / Double(guideColumns)
            for k in 1 ..< guideColumns {
                let x = x0 + Double(k) * pitch
                drawLine(Vector2(x, y0), Vector2(x, y1))
            }
        }

        // 3. The registers: heavy lines at every boundary, fine lines between.
        var top = y0
        for reg in dealt {
            let bottom = top + reg.height
            let r = pow(reg.ratio, 1 + 0.6 * breathing * sin(phase + reg.phase))
            let n = reg.lines
            // n lines make n + 1 intervals between the two heavy lines.
            let d0 = reg.height * (r - 1) / (pow(r, Double(n + 1)) - 1)
            let start = reg.flipped ? bottom : top
            let direction = reg.flipped ? -1.0 : 1.0
            var offset = 0.0
            stroke(graphite)
            for i in 0 ..< n {
                let d = d0 * pow(r, Double(i))
                offset += d
                let y = start + direction * offset
                strokeWeight(0.5 + 0.7 * pow(d0 / d, 1.2))
                drawLine(Vector2(x0, y), Vector2(x1, y))
                if doubled, y < midY {
                    let twin = y + twinFraction * d0
                    drawLine(Vector2(midX, twin), Vector2(x1, twin))
                }
            }
            top = bottom
        }
        stroke(ink)
        strokeWeight(heavyWeight)
        var boundary = y0
        drawLine(Vector2(x0, boundary), Vector2(x1, boundary))
        for reg in dealt {
            boundary += reg.height
            drawLine(Vector2(x0, boundary), Vector2(x1, boundary))
        }

        // 4. The verticals rising from the bottom edge.
        stroke(pencil)
        strokeWeight(0.9)
        for riser in risersDealt {
            drawLine(Vector2(riser.x, y1), Vector2(riser.x, y1 - riser.height))
        }
    }
}
