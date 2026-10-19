import Ollin

/// Strokes colored the way a soap film is colored. `Color.interference` is the
/// color a clear film of a given thickness shows, worked out from the light
/// its two faces send back out of step, so a ramp of it over a run of
/// thicknesses walks a real film's order: straw, magenta, blue, green, and on
/// into the pastels of a thick film. Each stroke here takes such a ramp through
/// `.alongPath`, from a thin end to a thick one, and the thicknesses swing back
/// and forth along the strokes with time so the colors travel. The ruler at the
/// bottom is the same color from 0 to 1,200 nanometers with the thicknesses
/// marked, and `ior` is the film's index: soap is about 1.35, oil about 1.45.
@main
final class PearlStrokes: Sketch {
    @Param("Index", 1.2 ... 1.8, icon: "drop") var ior = 1.35
    @Param("Thin end", 80 ... 500, icon: "arrow.left.to.line") var thin = 160.0
    @Param("Span", 100 ... 900, icon: "arrow.left.and.right") var span = 440.0
    @Param("Crawl", 0 ... 400, icon: "wind") var crawl = 120.0
    @Param("Weight", 6 ... 40, icon: "lineweight") var weight = 22.0

    override func setup() {
        noiseSeed(11)
    }

    override func draw() {
        background(Color(hex: 0x15161B))
        noFill()
        strokeCap(.round)
        strokeJoin(.round)

        // The strokes: a row of waves across the canvas, each a curve through
        // points that a noise field nudges, colored from thin to thick. The
        // thicknesses swing by `crawl` nanometers and back every eight seconds.
        let rows = 11
        let swing = crawl * (0.5 - 0.5 * cos(time * .tau / 8))
        let top = height * 0.08, bottom = height * 0.78
        for row in 0..<rows {
            let y = top + (bottom - top) * Double(row) / Double(rows - 1)
            let offset = Double(row) * 26 + swing
            let ramp = Ramp((0...32).map { i in
                Color.interference(thickness: thin + offset + span * Double(i) / 32, ior: ior)
            })
            stroke(.alongPath(ramp))
            strokeWeight(weight * scale * (1 - Double(row) / Double(rows) * 0.45))
            let points = (0...48).map { i -> Vector2 in
                let t = Double(i) / 48
                let x = width * (0.06 + 0.88 * t)
                let wave = signedNoise(t * 2.2 + Double(row) * 0.37, time * 0.12) * height * 0.035
                return Vector2(x, y + wave)
            }
            drawCurve(points)
        }

        // The ruler: the film's color from 0 to 1,200 nm, with the thicknesses marked.
        noStroke()
        let rulerY = height * 0.86, rulerH = height * 0.05
        let left = width * 0.06, right = width * 0.94
        let steps = 240
        for i in 0..<steps {
            let t = Double(i) / Double(steps)
            fill(Color.interference(thickness: t * 1200, ior: ior))
            drawRect(left + (right - left) * t, rulerY, (right - left) / Double(steps) + 1, rulerH)
        }
        fill(Color(white: 0.6))
        textFont(.system)
        textSize(13 * scale)
        textAlign(.center, .top)
        for nm in stride(from: 0, through: 1200, by: 200) {
            let x = left + (right - left) * Double(nm) / 1200
            drawRect(x - 0.5 * scale, rulerY + rulerH, scale, 6 * scale)
            drawText("\(nm) nm", x, rulerY + rulerH + 9 * scale)
        }
    }
}
