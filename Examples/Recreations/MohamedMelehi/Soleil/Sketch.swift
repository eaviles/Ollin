//  Recreation after Mohamed Melehi - the untitled panel of 1975 (cellulose
//  paint on wood, 110 x 95 cm) where a ribbon of green and pink waves parts
//  over a sun of rings, shown in New Waves at The Mosaic Rooms, London
//  (2019). A homage, not a reproduction, and not affiliated with or endorsed
//  by the artist or his estate.
//  https://hyperallergic.com/new-waves-mohamed-melehi-casablanca-art-school-mosaic-room/
//  https://www.lawrieshabibi.com/artists/167-mohamed-melehi/
//
//  An original Ollin interpretation, written from the painting. Nothing was
//  ported: the work is cellulose paint laid flat on a wooden panel, one color
//  up to the next with no edge between them.

import Foundation
import Ollin

/// The wave meeting the sun (Mohamed Melehi, 1975). A sun fills the panel:
/// rings of white, yellow, ochre and red around a lavender core, every ring
/// the same width, on a ground of night blue. Across it runs a ribbon of his
/// wave, green and pink turn and turn about, and the ribbon parts down its
/// middle. The two halves touch at the sun's center and open toward the
/// panel's corners, so the sun shows through the parting as a pinched core
/// and as two arcs of its rings at either end, and red fills the two corners
/// the ribbon closes off.
///
/// This sketch keeps the rule and deals the numbers. Every band edge is one
/// curve: the run along the parting, plus the wave across it, plus how far
/// the parting has opened at that point, and edge `j` on either side is the
/// first edge of that side moved over by `j` band widths. So neighbors share
/// their edge point for point, and every band is a whole lane from one end of
/// the run to the other. The parting opens as a hyperbola: each half keeps
/// `waist` from the middle line at the sun's center, and `opening` more for
/// every step along the run away from it. The two halves are the same wave,
/// so the ribbon reads as one ribbon pulled apart. `inks` colors the bands outward from the parting on both
/// sides, `rings` colors the sun from its edge in, its last color filling
/// the core, and every ring is `ringWidth` of the sun's radius.
///
/// The wave travels because the phase is the clock: one wavelength per
/// `seconds`, which is also the export loop, while the sun and the parting
/// hold still. The seed tilts the run a little, slides the sun along it, and
/// picks which ink meets the parting.
///
/// Every band exports as one closed outline and every ring as one circle, so
/// `--export-svg` gives the panel back as the regions the paint covers.
@main
final class Soleil: Sketch {
    @Param(count: 2 ... 6, icon: "paintpalette") var inks = Palette(Color(hex: 0xD97E92), Color(hex: 0x56BC44))
    @Param(count: 2 ... 8, icon: "sun.max") var rings = Palette(
        Color(hex: 0xEDEDE8), Color(hex: 0xF0C000), Color(hex: 0xE08C00), Color(hex: 0xE82A05), Color(hex: 0x6A7199))
    @Param(icon: "moon") var ground = Color(hex: 0x05041C)
    @Param(icon: "square.fill") var corners = Color(hex: 0xE83006)
    @Param(1 ... 12, icon: "rectangle.split.3x1") var bands = 7
    @Param(16 ... 120, icon: "arrow.left.and.right") var bandWidth = 62.0
    @Param(0 ... 100, icon: "water.waves") var amplitude = 56.0
    @Param(80 ... 600, icon: "ruler") var wavelength = 330.0
    @Param(0 ... 1.2, icon: "arrow.up.left.and.arrow.down.right") var opening = 0.35
    @Param(0 ... 120, icon: "hourglass") var waist = 0.0
    @Param(0.2 ... 0.6, icon: "circle") var sun = 0.49
    @Param(0.02 ... 0.2, icon: "circle.circle") var ringWidth = 0.105
    @Param(20 ... 70, icon: "angle") var angle = 40.0
    @Param(4 ... 60, icon: "clock") var seconds = 14.0

    override var canvasSize: CanvasSize { .size(940, 1080) }
    override var loopDuration: Double? { seconds }

    /// Edge points are this far apart along the run.
    private let step = 2.5

    override func draw() {
        background(ground)
        noStroke()
        randomSeed(variation)

        // 1. Deal the panel: the run's tilt, where the sun sits along it, and
        // which ink meets the parting.
        let theta = (angle + random(-6, 6)) * .pi / 180
        let along = random(-0.06, 0.06) * height
        let start = Int(random(Double(inks.count)))

        // 2. The axis. `u` runs up the parting, `n` across it toward the upper left.
        let u = Vector2(cos(theta), -sin(theta))
        let n = Vector2(-sin(theta), -cos(theta))
        let middle = Vector2(width / 2, height / 2) + u * along

        // 3. The sun: rings of one width from the edge in, the last color the core.
        let radius = sun * width
        let ring = min(ringWidth * radius, radius / Double(rings.count))
        for (i, color) in rings.enumerated() {
            fill(color)
            drawCircle(center: middle, radius: radius - Double(i) * ring)
        }

        // 4. Every edge is one curve: the run, the wave, and the parting.
        // The run reaches past every corner, so the ribbon's ends fall outside.
        let corners4 = [Vector2(0, 0), Vector2(width, 0), Vector2(0, height), Vector2(width, height)]
        let reach = corners4.map { ($0 - middle).length }.max()! + amplitude + 4
        let half = (reach / step / 2).rounded(.up) * step * 2
        let stations = Int((2 * half / step).rounded())
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        let ts = (0 ... stations).map { -half + Double($0) * step }
        let wave = ts.map { amplitude * sin(2 * .pi * ($0 / wavelength - phase)) }
        let parting = ts.map { (waist * waist + opening * opening * $0 * $0).squareRoot() }
        func edge(_ side: Double, _ offset: Double) -> [Vector2] {
            ts.indices.map { k in
                middle + u * ts[k] + n * (side * (parting[k] + offset) + wave[k])
            }
        }

        // 5. Each side: the bands outward from the parting, then the corner
        // beyond the last band, all of them the region between two edges.
        for side in [1.0, -1.0] {
            var inner = edge(side, 0)
            for j in 0 ..< bands {
                let outer = edge(side, Double(j + 1) * bandWidth)
                fill(inks[(start + j) % inks.count])
                // A band is concave wherever the wave turns, so it is a shape
                // that is triangulated, never a fan.
                drawShape(Shape(outer: inner + outer.reversed(), holes: []))
                inner = outer
            }
            fill(corners)
            drawShape(Shape(outer: inner + edge(side, Double(bands) * bandWidth + reach).reversed(), holes: []))
        }
    }
}
