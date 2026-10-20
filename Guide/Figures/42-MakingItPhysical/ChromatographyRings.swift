// figure: frame=0
//
// Guide figure (Chapter 42): chromatography rings over paper. One drop with
// its bands filled from an ink ramp and its fibers at the edge; three drops
// that spread into each other and stop where they meet; and the same three
// as nothing but lines, the way a pen would draw them.
import Ollin

final class ChromatographyRings: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    override func draw() {
        background(Color(hex: 0xF4EFE3))
        let tile = 276.0, gap = 16.0, top = 14.0
        let left = (width - tile * 3 - gap * 2) / 2
        let inks = Ramp([Color(hex: 0x1B1A2E), Color(hex: 0x24449A), Color(hex: 0x3F86B8),
                         Color(hex: 0xC43E7A), Color(hex: 0xE9B84A)])
        let dark = Color(hex: 0x1B1A2E)

        func fill(_ stain: Chromatography) {
            for drop in stain.drops {
                noStroke()
                for (band, ring) in zip(drop.bands, drop.rings) {
                    self.fill(inks.color(at: ring.tone).withAlpha(0.55 + 0.35 * (1 - ring.tone)))
                    drawShape(band)
                }
                noFill(); stroke(dark.withAlpha(0.5)); strokeWeight(0.9)
                for fiber in drop.fibers { drawPolyline(fiber) }
            }
        }

        // One drop, left.
        let one = Chromatography.spread(at: Vector2(left + tile / 2, top + tile / 2), radius: 112,
                                              rings: 5, fibers: 0.7, seed: 3)
        fill(one)

        // Three drops meeting, middle.
        let cx = left + tile + gap
        let three = Chromatography.spread([(Vector2(cx + 96, top + 104), 78),
                                                 (Vector2(cx + 190, top + 150), 86),
                                                 (Vector2(cx + 110, top + 206), 64)], seed: 5)
        fill(three)

        // The same three as lines, right.
        let lx = left + (tile + gap) * 2
        let lines = Chromatography.spread([(Vector2(lx + 96, top + 104), 78),
                                                 (Vector2(lx + 190, top + 150), 86),
                                                 (Vector2(lx + 110, top + 206), 64)], seed: 5)
        noFill(); stroke(dark); strokeWeight(1)
        for line in lines.lines { drawPolyline(line) }

        textFont(.system)
        noStroke()
        self.fill(Color(white: 0.4))
        textSize(17)
        textAlign(.center, .top)
        drawText("one drop", left + tile / 2, top + tile + 10)
        drawText("three drops meeting", cx + tile / 2, top + tile + 10)
        drawText("the same, for a pen", lx + tile / 2, top + tile + 10)
    }
}
