// figure: frame=0 themed
//
// Guide diagram (Chapter 31): a 3D scene written down as line work. Two panels
// of the same scene from the same camera: every edge the drawing considers,
// with the covered stretches drawn in, and then the drawing itself, where what
// the surfaces hide has been taken out. The paths are what `lineDrawing(of:)`
// returns, so the figure is the feature rather than a picture of it.
import Ollin
import OllinDiagram

final class SceneAsLines: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.35) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        camera(Camera3D(eye: Vector3(6.4, 4.6, 7.2), target: Vector3(0, 0.7, 0)))
        let scene: [Mesh] = [
            Mesh.box(width: 5, height: 0.4, depth: 5)
                .transformed(by: MeshInstance(position: Vector3(0, -0.2, 0))),
            Mesh.cylinder(radius: 0.6, height: 1.8, segments: 24)
                .transformed(by: MeshInstance(position: Vector3(-1.2, 0.9, 0.5))),
            Mesh.sphere(radius: 0.8, segments: 28, rings: 14)
                .transformed(by: MeshInstance(position: Vector3(1.1, 0.8, -0.3))),
            Mesh.box(size: 0.9)
                .transformed(by: MeshInstance(position: Vector3(0.3, 0.45, 1.5),
                                              rotation: Vector3(0, 0.5, 0))),
        ]
        let drawing = lineDrawing(of: scene)

        let panels = [Rectangle(x: 46, y: 44, width: 380, height: 250),
                      Rectangle(x: 454, y: 44, width: 380, height: 250)]
        diagramFrame(panels[0], title: "every edge it looks at", theme: theme)
        diagramFrame(panels[1], title: "what is left once the surface hides the rest", theme: theme)

        // The paths are canvas points already, so each panel is the same drawing
        // fitted into it. Both panels take the fit of the first, which holds
        // every line either of them draws, so the two are the same size.
        var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
        for line in drawing.paths + drawing.hidden {
            for point in line.points {
                low = Vector2(min(low.x, point.x), min(low.y, point.y))
                high = Vector2(max(high.x, point.x), max(high.y, point.y))
            }
        }
        let span = high - low
        let factor = min(panels[0].width * 0.88 / max(span.x, 1),
                         panels[0].height * 0.88 / max(span.y, 1))
        let middle = (low + high) / 2

        for (index, panel) in panels.enumerated() {
            withState {
                translate(panel.center.x - factor * middle.x,
                          panel.center.y - factor * middle.y)
                scale(factor, factor)
                noFill()
                strokeJoin(.round)
                if index == 0 {
                    stroke(soft)
                    strokeWeight(1.6 / factor)
                    for line in drawing.hidden { drawPolyline(line.points, closed: line.isClosed) }
                }
                stroke(ink)
                strokeWeight(2.0 / factor)
                for line in drawing.paths { drawPolyline(line.points, closed: line.isClosed) }
            }
        }

        diagramCaption("the same paths, and the drawing is which of them are kept", at: 340, theme: theme)
    }
}
