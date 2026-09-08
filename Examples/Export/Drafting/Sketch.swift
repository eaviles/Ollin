import Ollin

/// Drafting: the layers a shop program will open, before the file is written.
/// A laser shop tells its three jobs apart by color: the outline to cut, the
/// fold lines to score, and the pattern to engrave. `--export-dxf` writes each
/// color as its own layer, so the sketch's colors are the handle. This sketch
/// draws a lidded box's panel that way, and plans each color through
/// `DXF.drafting(_:in:)` to list the layers beside it, with the entities each
/// holds.
///
/// The same frame writes a `.dxf` a shop program opens in millimeters:
///
/// ```sh
/// swift run Example-Export-Drafting --export-dxf /tmp/panel.dxf
/// swift run Example-Export-Drafting --export-dxf /tmp/panel.dxf --dxf-width 120 --dxf-margin 5
/// ```
@main
final class Drafting_Example: Sketch {
    @Param("Rays", 6 ... 36, icon: "sun.max", group: "Engraving") var rays = 18
    @Param("Waves", 1 ... 6, icon: "water.waves", group: "Engraving") var waves = 3
    @Param(icon: "square.stack.3d.up", group: "View") var legend = true

    private let cut = Color(hex: 0x1B1040)
    private let score = Color(hex: 0xC94B3F)
    private let engrave = Color(hex: 0x3F86C9)

    override func draw() {
        background(Color(hex: 0xF3EBDD))
        // The panel sits in the left two thirds; the legend takes the rest.
        let panel = Rectangle(x: width * 0.08, y: height * 0.14, width: width * 0.56, height: height * 0.72)

        let outline = self.outline(panel)
        let folds = self.folds(panel)
        let pattern = self.pattern(panel)

        noFill()
        stroke(cut)
        strokeWeight(3)
        drawPolygon(outline.points)
        stroke(score)
        strokeWeight(2)
        for fold in folds { drawLine(fold.points[0], fold.points[1]) }
        stroke(engrave)
        strokeWeight(1.5)
        for curve in pattern { drawPolyline(curve.points) }

        guard legend, !isVectorExporting else { return }
        let canvas = Rectangle(x: 0, y: 0, width: width, height: height)
        let plans: [(String, Color, [Contour])] = [
            ("cut", cut, [outline]), ("score", score, folds), ("engrave", engrave, pattern),
        ]
        noStroke()
        fill(cut)
        textSize(20)
        textAlign(.left, .middle)
        drawText("Three colors, three layers", width * 0.7, height * 0.09)
        textSize(22)
        var y = height * 0.2
        for (job, color, contours) in plans {
            let plan = DXF(width: 150).drafting(contours, in: canvas)
            fill(color)
            drawRect(width * 0.7, y - 11, 22, 22)
            fill(cut)
            drawText("color-" + hex(color), width * 0.7 + 34, y)
            fill(Color(hex: 0x6B6258))
            textSize(17)
            drawText("\(job), \(plan.entities.count) entit\(plan.entities.count == 1 ? "y" : "ies")",
                     width * 0.7 + 34, y + 30)
            textSize(22)
            y += height * 0.14
        }
        fill(Color(hex: 0x6B6258))
        textSize(15)
        drawText("--export-dxf panel.dxf writes them", width * 0.7, height * 0.86)
        drawText("as a shop program reads them", width * 0.7, height * 0.89)
    }

    /// The panel's outline: a rectangle with a tab on each short side.
    private func outline(_ r: Rectangle) -> Contour {
        let tab = r.height * 0.18
        let inset = r.height * 0.3
        return Contour([
            Vector2(r.x, r.y), Vector2(r.topRight.x, r.y),
            Vector2(r.topRight.x, r.y + inset), Vector2(r.topRight.x + tab, r.y + inset + tab * 0.4),
            Vector2(r.topRight.x + tab, r.bottomRight.y - inset - tab * 0.4), Vector2(r.topRight.x, r.bottomRight.y - inset),
            Vector2(r.topRight.x, r.bottomRight.y), Vector2(r.x, r.bottomRight.y),
            Vector2(r.x, r.bottomRight.y - inset), Vector2(r.x - tab, r.bottomRight.y - inset - tab * 0.4),
            Vector2(r.x - tab, r.y + inset + tab * 0.4), Vector2(r.x, r.y + inset),
        ], closed: true)
    }

    /// Two fold lines, a fifth of the way in from each short side.
    private func folds(_ r: Rectangle) -> [Contour] {
        [0.2, 0.8].map { t in
            Contour([Vector2(r.x + r.width * t, r.y), Vector2(r.x + r.width * t, r.bottomRight.y)], closed: false)
        }
    }

    /// The engraving: rays from the panel's center, each waving as it goes.
    private func pattern(_ r: Rectangle) -> [Contour] {
        let center = r.center
        let reach = r.width * 0.28
        return (0 ..< rays).map { k in
            let a = Double(k) / Double(rays) * .tau
            let points = (0 ... 40).map { i -> Vector2 in
                let t = Double(i) / 40
                let across = sin(t * .pi * Double(waves)) * reach * 0.08
                return center + Vector2(cos(a), sin(a)) * (reach * 0.2 + reach * 0.8 * t)
                    + Vector2(-sin(a), cos(a)) * across
            }
            return Contour(points, closed: false)
        }
    }

    private func hex(_ color: Color) -> String {
        String(format: "%02X%02X%02X", Int((color.red * 255).rounded()),
               Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
    }
}
