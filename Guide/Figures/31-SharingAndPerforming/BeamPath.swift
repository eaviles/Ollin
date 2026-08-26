// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a laser makes of a drawing. The same line
// work twice: on the left as it is drawn, on the right as one dot traces it,
// with the beam's own footsteps as points and the dark travel between shapes
// as thin lines. Both panels are measured from the same optimized stream, not
// written in.
import Ollin
import OllinDiagram
import OllinLaser

final class BeamPath: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        let source = Rectangle(x: 0, y: 0, width: 100, height: 100)
        var optimizer = LaserOptimizer()
        optimizer.spacing = 0.055          // coarse, so the footsteps are countable
        optimizer.travelSpacing = 0.11
        optimizer.cornerDwell = 2
        optimizer.blankingDwell = 2
        let stream = optimizer.stream(artwork(in: source))

        let left = Rectangle(x: 55, y: 50, width: 330, height: 330)
        let right = Rectangle(x: 495, y: 50, width: 330, height: 330)
        drawAsDrawn(artwork(in: source), in: left, from: source)
        drawAsScanned(stream, in: right)
        diagramCaption("the same drawing, and the path one dot takes to make it",
                       at: 432, theme: theme)
    }

    /// The picture as a sketch draws it: outlines, and nothing about time.
    private func drawAsDrawn(_ frame: LaserFrame, in panel: Rectangle, from source: Rectangle) {
        diagramFrame(panel, title: "as drawn", theme: theme)
        let inset = 26.0
        let scale = (panel.width - 2 * inset) / source.width
        func mapped(_ p: Vector2) -> Vector2 {
            Vector2(panel.x + inset + p.x * scale, panel.y + inset + p.y * scale)
        }
        withState {
            noFill()
            stroke(theme.ink)
            strokeWeight(2.2)
            for path in frame.paths {
                drawShape(Shape(contours: [Contour(path.points.map(mapped), closed: path.isClosed)]))
            }
        }
        drawText("\(frame.paths.count) shapes", panel.x + panel.width / 2,
                 panel.y + panel.height + 14, size: 17, color: theme.muted,
                 align: .center, .top)
    }

    /// The same picture as the projector receives it: a list of positions, each
    /// one lit or dark.
    private func drawAsScanned(_ stream: LaserStream, in panel: Rectangle) {
        diagramFrame(panel, title: "as the beam traces it", theme: theme)
        let inset = 26.0
        let radius = (panel.width - 2 * inset) / 2
        let middle = Vector2(panel.x + panel.width / 2, panel.y + inset + radius)
        func mapped(_ p: Vector2) -> Vector2 {
            Vector2(middle.x + p.x * radius, middle.y - p.y * radius)
        }
        withState {
            noFill()
            for i in 1..<stream.points.count {
                let a = stream.points[i - 1], b = stream.points[i]
                if a.isBlanked || b.isBlanked {
                    stroke(theme.accent)
                    strokeWeight(1.2)
                } else {
                    stroke(theme.ink)
                    strokeWeight(2.2)
                }
                drawLine(mapped(a.position), mapped(b.position))
            }
            noStroke()
            for point in stream.points {
                fill(point.isBlanked ? theme.accent : theme.ink)
                drawCircle(center: mapped(point.position), radius: 3)
            }
        }
        drawText("\(stream.points.count) points, \(stream.blankedCount) of them dark",
                 panel.x + panel.width / 2, panel.y + panel.height + 14,
                 size: 17, color: theme.muted, align: .center, .top)
    }

    /// A ring and a small square, far enough apart that the beam has to travel
    /// in the dark to get from one to the other.
    private func artwork(in source: Rectangle) -> LaserFrame {
        var frame = LaserFrame(canvas: source)
        let ring = (0..<28).map { i -> Vector2 in
            let angle = Double(i) / 28 * 2 * .pi
            return Vector2(42 + cos(angle) * 26, 44 + sin(angle) * 26)
        }
        frame.add(ring, color: .black, closed: true)
        frame.add([Vector2(74, 74), Vector2(92, 74), Vector2(92, 92), Vector2(74, 92)],
                  color: .black, closed: true)
        return frame
    }
}
