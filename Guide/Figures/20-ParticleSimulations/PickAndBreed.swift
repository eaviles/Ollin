// figure: frame=0 themed
//
// Guide diagram (Chapter 20): evolution with no score. Sixteen ornaments
// drawn straight from sixteen genomes; two get picked (the ringed pair);
// one breeding later the grid is sixteen variations on the two you liked.
// The population carries its own seed, so the figure replays identically.
import Ollin

final class PickAndBreed: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x232020) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }
    let picked = [5, 10]

    override func draw() {
        background(paper)

        let panels = [
            Rectangle(x: 80, y: 54, width: 330, height: 330),
            Rectangle(x: 470, y: 54, width: 330, height: 330),
        ]

        var pool = population(count: 16, genes: 8, seed: 7)
        drawGrid(pool, in: panels[0], ringing: picked)

        pool.breed(from: picked)
        drawGrid(pool, in: panels[1], ringing: [])

        let titles = ["generation one: pick two", "one breeding later"]
        for (i, panel) in panels.enumerated() {
            noStroke()
            fill(ink)
            textSize(16)
            textAlign(.left, .middle)
            drawText(titles[i], panel.x, panel.y - 18)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("no score anywhere: the next sixteen are variations on the two you liked",
                 width / 2, 414)
    }

    func drawGrid(_ pool: Population, in panel: Rectangle, ringing: [Int]) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(panel)
        let cell = panel.width / 4
        for (i, g) in pool.enumerated() {
            let cx = panel.x + (Double(i % 4) + 0.5) * cell
            let cy = panel.y + (Double(i / 4) + 0.5) * cell
            withState {
                translate(cx, cy)
                drawOrnament(g, radius: cell * 0.42)
            }
            if ringing.contains(i) {
                noFill()
                stroke(accent)
                strokeWeight(2.5)
                drawRect(Rectangle(x: cx - cell / 2 + 3, y: cy - cell / 2 + 3,
                                   width: cell - 6, height: cell - 6))
            }
        }
    }

    func drawOrnament(_ g: Genome, radius: Double) {
        let arms = g.value(0, in: 3 ... 11)
        let hue = g.value(1, in: 0.0 ... 1.0)
        let rings = g.value(2, in: 1 ... 4)
        let reach = g.value(3, in: 0.55 ... 0.95) * radius
        let dot = g.value(4, in: 0.05 ... 0.14) * radius
        let twist = g.value(5, in: -0.9 ... 0.9)
        let ringShare = g.value(6, in: 0.25 ... 0.6)
        let tone = Color(hue: hue, saturation: 0.55, brightness: 0.62)

        noFill()
        stroke(tone.withAlpha(0.85))
        strokeWeight(1.6)
        for r in 1 ... rings {
            drawCircle(0, 0, Double(r) / Double(rings) * reach * ringShare)
        }

        noStroke()
        fill(ink.withAlpha(0.85))
        for arm in 0 ..< arms {
            let base = Double(arm) / Double(arms) * .tau
            for step in 1 ... 5 {
                let t = Double(step) / 5
                let a = base + twist * t
                let r = reach * (ringShare + (1 - ringShare) * t)
                fill(step == 5 ? tone : ink.withAlpha(0.8))
                drawCircle(cos(a) * r, sin(a) * r, dot * (1.15 - t * 0.5))
            }
        }
    }
}
