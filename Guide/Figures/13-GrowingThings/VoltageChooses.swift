// figure: frame=0 themed
//
// Guide diagram (Chapter 13): dielectric breakdown. Left, the rule: the
// solved field around a young discharge, washed light where the potential is
// high, with the frontier dotted by each candidate's actual growth weight,
// large at the tips and vanishing in the crevices. Right, what that rule
// grows at the lightning exponent, drawn with pipe-model widths.
import Ollin

final class VoltageChooses: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }
    let wash = Color(hex: 0x6B5AE0)

    var young: DielectricBreakdown!
    var grown: DielectricBreakdown!

    override func setup() {
        let left = panel(0), right = panel(1)
        young = DielectricBreakdown(seeds: [left.center], in: left,
                                    resolution: 44, eta: 1.9,
                                    maxSites: 90, seed: 5)
        young.step(90)
        grown = DielectricBreakdown(seeds: [right.center], in: right,
                                    resolution: 84, eta: 1.9,
                                    maxSites: 640, seed: 12)
        grown.step(640)
    }

    func panel(_ i: Int) -> Rectangle {
        Rectangle(x: 50 + Double(i) * 420, y: 60, width: 370, height: 340)
    }

    override func draw() {
        background(paper)
        let left = panel(0), right = panel(1)

        // Left: the field as a wash (light where the potential is high),
        // the frontier dotted by the candidates' weights.
        noStroke()
        let block = 5.0
        var y = left.y
        while y < left.y + left.height {
            var x = left.x
            while x < left.x + left.width {
                let p = young.potential(at: Vector2(x + block / 2, y + block / 2))
                fill(wash.withAlpha(0.05 + (1 - p) * 0.30))
                drawRect(x, y, block, block)
                x += block
            }
            y += block
        }

        stroke(ink)
        strokeWeight(3)
        strokeCap(.round)
        for (a, b) in young.segments { drawLine(a, b) }

        // The frontier: every empty lattice neighbor of the discharge, its
        // dot area the weight the model actually uses (potential to eta).
        let cell = left.width / 44
        var seen = Set<String>()
        noStroke()
        fill(accent)
        for site in young.sites {
            for offset in [Vector2(cell, 0), Vector2(-cell, 0),
                           Vector2(0, cell), Vector2(0, -cell)] {
                let q = site.position + offset
                let phi = young.potential(at: q)
                guard phi > 0 else { continue }
                let key = "\(Int(q.x.rounded()))-\(Int(q.y.rounded()))"
                guard seen.insert(key).inserted else { continue }
                drawCircle(q.x, q.y, 1.2 + 9 * pow(phi, 1.9))
            }
        }

        // Right: the grown figure at the same exponent, trunks thickened by
        // the pipe model.
        let widths = grown.thicknesses(tipWidth: 0.9, exponent: 2.0)
        stroke(ink)
        for (i, site) in grown.sites.enumerated() {
            guard let parent = site.parent else { continue }
            strokeWeight(widths[i])
            drawLine(grown.sites[parent].position, site.position)
        }

        for r in [left, right] {
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)
        }

        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .top)
        drawText("the solved field, dotted where it will strike",
                 left.center.x, left.y + left.height + 16)
        drawText("what eta = 1.9 grows, trunks thickened",
                 right.center.x, right.y + right.height + 16)
    }
}
