// figure: frame=150 themed
//
// Guide diagram (Chapter 10): who goes where when a cloud gathers into a word.
// The same scatter of dots above the same word twice. On the left every dot
// is sent to the letter point that makes everyone's travel, added up, the
// least, and no two roads cross. On the right each dot in turn grabs the
// nearest point still free, and the roads tangle.
import Ollin
import OllinDiagram

final class GatherIntoLetters: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let panels = [Rectangle(x: 40, y: 40, width: 390, height: 420),
                  Rectangle(x: 450, y: 40, width: 390, height: 420)]
    let count = 160

    var cloud: [Vector2] = []
    var letters: [Vector2] = []
    var glyphs: [Shape] = []
    var optimal = Matching.optimal([Vector2](), [Vector2]())
    var greedy = Matching.greedy([Vector2](), [Vector2]())

    override func setup() {
        seed(3)
        // The word's points, as many per letter as its area deserves, in the
        // lower half of the first panel; the second panel shifts them across.
        textSize(170)
        let shapes = textToShapes("GO", at: .zero)
        let boxes = shapes.compactMap(\.bounds)
        let box = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        let shift = Vector2(panels[0].center.x, panels[0].y + 300) - box.center
        glyphs = shapes.map { shape in
            Shape(contours: shape.contours.map { Contour($0.points.map { $0 + shift }, closed: true) })
        }
        let area = shapes.reduce(0.0) { $0 + $1.area }
        for (k, shape) in shapes.enumerated() {
            let share = k == shapes.count - 1
                ? count - letters.count
                : Int((Double(count) * shape.area / area).rounded())
            letters += randomPoints(in: shape, count: share).map { $0 + shift }
        }
        // The cloud sits in the upper part of the panel, so every road runs down.
        let sky = Rectangle(x: panels[0].x + 30, y: panels[0].y + 28, width: panels[0].width - 60, height: 130)
        cloud = (0 ..< count).map { _ in randomVector(in: sky) }
        optimal = Matching.optimal(cloud, letters)
        greedy = Matching.greedy(cloud, letters)
    }

    override func draw() {
        background(theme.paper)
        textAlign(.center)

        for (k, match) in [optimal, greedy].enumerated() {
            let panel = panels[k]
            let shift = panel.corner - panels[0].corner
            noFill()
            stroke(theme.ink(0.12))
            strokeWeight(1)
            drawRect(panel)

            // The word itself, faint, so the destination reads as letters.
            noStroke()
            fill(theme.ink(0.07))
            withState {
                translate(shift)
                for glyph in glyphs { drawShape(glyph) }
            }

            // Every road, and each dot part of the way along it.
            stroke(theme.ink(0.22))
            strokeWeight(1)
            for pair in match.pairs {
                drawLine(cloud[pair.first] + shift, letters[pair.second] + shift)
            }
            noStroke()
            fill(theme.ink(0.3))
            for target in letters { drawCircle(center: target + shift, radius: 2) }
            fill(theme.accent)
            for pair in match.pairs {
                let at = (cloud[pair.first] + shift).lerp(to: letters[pair.second] + shift, 0.4)
                drawCircle(center: at, radius: 3.2)
            }

            fill(theme.ink)
            textSize(17)
            let travel = Int(match.totalCost / 100) * 100
            drawText(k == 0 ? "least total, \(travel) points: no road crosses"
                            : "greedy, \(travel) points: the roads cross",
                     panel.center.x, panel.y + panel.height + 28)
        }

        fill(theme.ink)
        textSize(21)
        drawText("the same dots and the same word, paired two ways", width / 2, 522)
    }
}
