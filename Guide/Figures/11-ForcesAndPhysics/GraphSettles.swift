// figure: frame=0 themed
//
// Guide diagram (Chapter 11): the same graph at three temperatures. Left, the
// seeded random start: a huddle of tangled edges. Middle, mid-cooling: edges
// evening out, crossings resolving. Right, settled: an even web, frozen.
import Ollin
import OllinDiagram

final class GraphSettles: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var edgeInk: Color { theme.ink(0.55) }
    var accent: Color { theme.accent }

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    var layouts: [ForceLayout] = []
    var hub = 0

    override func setup() {
        layouts = []
        // A small scale-free web: each newcomer joins a node picked in
        // proportion to its degree, so a few hubs grow rich.
        var rng = SplitMix64(seed: 20)
        var edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 0)]
        var stubs = [0, 1, 1, 2, 2, 0]
        for i in 3 ..< 26 {
            let parent = stubs[Int(Double.random(in: 0 ..< 1, using: &rng) * Double(stubs.count))]
            edges.append((i, parent))
            stubs.append(i)
            stubs.append(parent)
            if Double.random(in: 0 ..< 1, using: &rng) < 0.3 {
                let second = stubs[Int(Double.random(in: 0 ..< 1, using: &rng) * Double(stubs.count))]
                if second != i, second != parent {
                    edges.append((i, second))
                    stubs.append(i)
                    stubs.append(second)
                }
            }
        }
        var degrees = [Int](repeating: 0, count: 26)
        for (a, b) in edges {
            degrees[a] += 1
            degrees[b] += 1
        }
        hub = degrees.indices.max { degrees[$0] < degrees[$1] } ?? 0

        // Three copies of the same seeded layout, run to three moments.
        for (panel, steps) in [(left, 0), (middle, 30), (right, -1)] {
            let layout = ForceLayout(count: 26, edges: edges,
                                     in: panel.inset(by: 26), seed: 20)
            layout.idealDistance *= 1.5
            if steps < 0 {
                layout.settle()
            } else {
                layout.step(steps)
            }
            layouts.append(layout)
        }
    }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = ["a seeded random start", "cooling: bold, then gentle",
                      "settled: an even web"]
        for (i, layout) in layouts.enumerated() {
            frame([left, middle, right][i], title: titles[i])
            stroke(edgeInk)
            strokeWeight(1.4)
            noFill()
            for edge in layout.edges {
                drawLine(layout.positions[edge.a], layout.positions[edge.b])
            }
            noStroke()
            for node in 0 ..< layout.count {
                fill(node == hub ? accent : ink)
                drawCircle(center: layout.positions[node],
                           radius: node == hub ? 6 : 4)
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("nobody places a node: repulsion spreads them, edges pull, cooling freezes",
                 width / 2, 462)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
