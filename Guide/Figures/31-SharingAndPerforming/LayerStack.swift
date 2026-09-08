// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a DXF export sorts a drawing into. On the
// left a coaster drawn in three colors: the outline to cut, a ring to score,
// and a rosette to engrave. On the right the same drawing pulled apart into
// the three layers the file holds, one per color, each labeled with the
// layer's name and the entities on it. The counts are read from the planner,
// not written in.
import Ollin
import OllinDiagram

final class LayerStack: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let cut = Color(hex: 0x1B1040)
    let score = Color(hex: 0xC94B3F)
    let engrave = Color(hex: 0x3F86C9)

    /// The design, in a 100-unit source square: each layer's contours.
    struct Layer {
        var name: String
        var job: String
        var color: Color
        var contours: [Contour]
    }

    lazy var layers: [Layer] = {
        let center = Vector2(50, 50)
        func ring(_ radius: Double, count: Int = 72) -> Contour {
            Contour((0 ..< count).map { k in
                let a = Double(k) / Double(count) * .tau
                return center + Vector2(cos(a), sin(a)) * radius
            }, closed: true)
        }
        var petals: [Contour] = []
        for k in 0 ..< 8 {
            let a = Double(k) / 8 * .tau
            var points: [Vector2] = []
            for i in 0 ... 24 {
                let t = Double(i) / 24
                let r = 12 + 20 * sin(t * .pi)
                let spread = (t - 0.5) * 0.55
                points.append(center + Vector2(cos(a + spread), sin(a + spread)) * r)
            }
            petals.append(Contour(points, closed: false))
        }
        return [
            Layer(name: "color-1B1040", job: "cut", color: cut, contours: [ring(46)]),
            Layer(name: "color-C94B3F", job: "score", color: score, contours: [ring(38, count: 48), ring(9, count: 24)]),
            Layer(name: "color-3F86C9", job: "engrave", color: engrave, contours: petals),
        ]
    }()

    override func draw() {
        background(theme.paper)
        textFont(OutlineFont.system)
        let source = Rectangle(x: 0, y: 0, width: 100, height: 100)

        let left = Rectangle(x: 60, y: 46, width: 320, height: 320)
        diagramFrame(left, title: "the drawing, in three colors", theme: theme)
        for layer in layers { drawContours(layer.contours, in: left, from: source, color: layer.color, weight: 2.5) }

        // The layers, pulled apart: a plate each, stepping up and to the right.
        let plateWidth = 200.0, plateHeight = 120.0
        for (index, layer) in layers.enumerated() {
            let plate = Rectangle(x: 454 + Double(index) * 26, y: 232 - Double(index) * 86,
                                  width: plateWidth, height: plateHeight)
            noStroke()
            fill(theme.ink(0.05))
            drawRect(plate)
            noFill()
            stroke(theme.ink(0.16))
            strokeWeight(1.5)
            drawRect(plate)
            // The plate is a squashed view of the square, so the rings read as
            // ellipses on a tilted sheet.
            let panel = Rectangle(x: plate.x + 20, y: plate.y + 12, width: plate.width - 40, height: plate.height - 24)
            drawContours(layer.contours, in: panel, from: source, color: layer.color, weight: 2)

            let plan = DXF(width: 100).drafting(layer.contours, in: source)
            let count = plan.entities.count
            noStroke()
            fill(theme.ink)
            textSize(14)
            textAlign(.left, .middle)
            drawText(layer.name, plate.topRight.x + 12, plate.y + 20)
            fill(theme.ink(0.5))
            textSize(12)
            drawText("\(layer.job), \(count) entit\(count == 1 ? "y" : "ies")", plate.topRight.x + 12, plate.y + 42)
        }
        diagramFrame(Rectangle(x: 440, y: 46, width: 400, height: 320), title: "the layers the file holds", theme: theme)
        diagramCaption("each color is a layer, and a shop reads a layer as a job", at: 412, theme: theme)
    }

    private func drawContours(_ contours: [Contour], in panel: Rectangle, from source: Rectangle,
                              color: Color, weight: Double) {
        noFill()
        stroke(color)
        strokeWeight(weight)
        for contour in contours {
            let points = contour.points.map { p in
                Vector2(panel.x + (p.x - source.x) / source.width * panel.width,
                        panel.y + (p.y - source.y) / source.height * panel.height)
            }
            if contour.isClosed { drawPolygon(points) } else { drawPolyline(points) }
        }
    }
}
