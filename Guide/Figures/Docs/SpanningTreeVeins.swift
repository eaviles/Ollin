// figure: frame=0 themed
//
// Docs diagram (Generators/SpanningTree.md): the same dots twice. Left, a
// clustered stipple on its own. Right, the minimum spanning tree drawn
// through it: trunks where the dots crowd, twigs feathering out, branches
// and never a loop.
import Ollin

final class SpanningTreeVeins: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        seed(11)
        var dots: [Vector2] = []
        let clusters = [Vector2(90, 90), Vector2(210, 120), Vector2(140, 230)]
        for center in clusters {
            for _ in 0..<38 {
                let p = center + Vector2(randomGaussian() * 34, randomGaussian() * 34)
                if p.x > 12, p.x < 288, p.y > 12, p.y < 288 { dots.append(p) }
            }
        }
        for _ in 0..<26 {
            dots.append(Vector2(random(15, 285), random(15, 285)))
        }

        let tree = spanningTree(through: dots)

        withState {
            translate(left.x, left.y)
            noStroke()
            fill(ink)
            for dot in dots { drawCircle(center: dot, radius: 2.6) }
        }

        withState {
            translate(right.x, right.y)
            noFill()
            stroke(accent)
            strokeWeight(1.8)
            for chain in tree { drawPolyline(chain.points) }
            noStroke()
            fill(ink)
            for dot in dots { drawCircle(center: dot, radius: 2.2) }
        }

        frame(left, title: "the dots")
        frame(right, title: "the tree: branches, no loops")

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("the shortest line work that still reaches every dot",
                 width / 2, 396)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
