// figure: frame=0 themed
//
// Guide diagram (Chapter 29): what modulation puts in. Four columns, each the
// arithmetic one operator pushing another does: the carrier's wave on top and
// the tones it contains below, measured from the wave itself over two of its
// periods. The first has nothing above its own note, the middle two grow a
// harmonic series as the index climbs, and the fourth, at a ratio that is not
// a whole number, lands between the harmonics instead of on them.
import Ollin

final class Modulation: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.14) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xC1553B) }

    /// One operator pushing another: a sine whose phase is bent by a second
    /// sine running at `ratio` times the note, by `index` radians.
    func wave(_ t: Double, index: Double, ratio: Double) -> Double {
        sin(t * .tau + index * sin(t * .tau * ratio))
    }

    /// How much of the wave sits at each multiple of half the note, measured
    /// over two periods so a half-integer partial has somewhere to land.
    func partials(index: Double, ratio: Double) -> [Double] {
        let n = 4096
        var out: [Double] = []
        for half in 1 ... 24 {
            let k = Double(half) / 2
            var re = 0.0, im = 0.0
            for i in 0 ..< n {
                let t = Double(i) / Double(n) * 2          // two periods
                let v = wave(t, index: index, ratio: ratio)
                re += v * cos(t * .tau * k)
                im -= v * sin(t * .tau * k)
            }
            out.append((re * re + im * im).squareRoot() / Double(n) * 2)
        }
        return out
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let columns: [(String, Double, Double)] = [
            ("a plain sine", 0, 1),
            ("index 2, ratio 1", 2, 1),
            ("index 6, ratio 1", 6, 1),
            ("index 4, ratio 3.5", 4, 3.5),
        ]
        for (i, column) in columns.enumerated() {
            let x = 42 + Double(i) * 204
            panel(x: x, label: column.0, index: column.1, ratio: column.2)
        }

        noStroke()
        fill(ink.withAlpha(0.6))
        textSize(15)
        textAlign(.center, .top)
        drawText("dark bars are the note's own harmonics, red ones fall between them",
                 width / 2, 424)
        fill(ink)
        textSize(20)
        drawText("modulation puts in the harmonics a filter could only have taken away",
                 width / 2, 486)
    }

    func panel(x: Double, label: String, index: Double, ratio: Double) {
        let w = 176.0

        // The wave, over two periods of the note.
        stroke(faint); strokeWeight(1)
        drawLine(x, 128, x + w, 128)
        noFill(); stroke(ink); strokeWeight(2)
        drawShape { path in
            for i in 0 ... 300 {
                let t = Double(i) / 300 * 2
                let p = Vector2(x + Double(i) / 300 * w,
                                128 - wave(t, index: index, ratio: ratio) * 52)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
        }

        // What it contains, one bar per half harmonic.
        let bars = partials(index: index, ratio: ratio)
        let peak = max(bars.max() ?? 1, 0.001)
        noStroke()
        for (j, value) in bars.enumerated() {
            let bx = x + Double(j) * (w / 24) + 2
            let h = value / peak * 96
            fill((j + 1) % 2 == 0 ? ink : accent)
            drawRect(bx, 340 - h, w / 24 - 4, max(h, 0.6))
        }
        stroke(faint); strokeWeight(1)
        drawLine(x, 340, x + w, 340)

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.center, .top)
        drawText(label, x + w / 2, 360)
    }
}
