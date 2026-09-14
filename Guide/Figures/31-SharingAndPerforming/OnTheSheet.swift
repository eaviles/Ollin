// figure: frame=0 themed
//
// Guide diagram (Chapter 31): a named sheet doing the arithmetic. One line
// drawing, a rose curve inside its canvas, is planned four times through the
// G-code planner itself, `GCode(.plotter(), paper:)`, and each sheet is drawn
// to one scale with the planned route inside it: A3 lying wide with a wider
// margin, A4, A4 again for a canvas taller than the sheet's shape, and US
// letter. The millimeters under each sheet are read back from the planner's
// own measurement of the canvas border, never worked out by the figure, so
// what the figure shows is what the program's header says.
import Ollin
import OllinDiagram

final class OnTheSheet: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    struct Plan {
        var spelling: String
        var settings: GCode
        var canvas: Rectangle
        var flag: String
    }

    let plans: [Plan] = [
        Plan(spelling: "paper: .a3.landscape, margin: 15", settings: GCode(.plotter(), paper: .a3.landscape, margin: 15),
             canvas: Rectangle(x: 0, y: 0, width: 1080, height: 1080), flag: "--gcode-paper a3"),
        Plan(spelling: "paper: .a4", settings: GCode(.plotter(), paper: .a4),
             canvas: Rectangle(x: 0, y: 0, width: 1080, height: 1080), flag: "--gcode-paper a4"),
        Plan(spelling: "paper: .a4, a tall canvas", settings: GCode(.plotter(), paper: .a4),
             canvas: Rectangle(x: 0, y: 0, width: 1080, height: 1920), flag: "held to the sheet's height"),
        Plan(spelling: "paper: .usLetter", settings: GCode(.plotter(), paper: .usLetter),
             canvas: Rectangle(x: 0, y: 0, width: 1080, height: 1080), flag: "--gcode-paper letter"),
    ]

    /// Pixels per millimeter, one scale for every sheet.
    let px = 0.66

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let floor = 300.0
        var x = 36.0
        for plan in plans {
            let sheet = plan.settings.paper ?? .a4
            let w = sheet.width * px, h = sheet.height * px
            let rect = Rectangle(x: x, y: floor - h, width: w, height: h)

            // The sheet, and the margin the planner keeps clear.
            fill(theme.dark ? Color(hex: 0x1C232C) : .white)
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(rect)
            let m = plan.settings.margin * px
            noFill()
            stroke(theme.ink(0.18))
            strokeWeight(1)
            drawRect(Rectangle(x: rect.x + m, y: rect.y + m, width: w - 2 * m, height: h - 2 * m))

            // The route the planner made, in the millimeters it chose.
            let route = plan.settings.toolpath(drawing(in: plan.canvas), in: plan.canvas)
            let border = plan.settings.toolpath([Contour(corners(of: plan.canvas), closed: true)], in: plan.canvas)
            let mmPerUnit = border.drawnLength / (2 * (plan.canvas.width + plan.canvas.height))
            let drawnW = plan.canvas.width * mmPerUnit, drawnH = plan.canvas.height * mmPerUnit
            let origin = Vector2(rect.x + m, rect.y + h - m)     // the margin corner, bottom-left
            noFill()
            stroke(theme.ink(0.35))
            strokeWeight(1)
            drawRect(Rectangle(x: origin.x, y: origin.y - drawnH * px, width: drawnW * px, height: drawnH * px))
            stroke(theme.accent)
            strokeWeight(1.2)
            for path in route.paths {
                let points = path.points.map { p in
                    Vector2(origin.x + p.x * mmPerUnit * px,
                            origin.y - (plan.canvas.height - p.y) * mmPerUnit * px)
                }
                drawPolyline(points, closed: path.isClosed)
            }

            // What it is, above; what it came to, below.
            noStroke()
            drawText(plan.spelling, rect.center.x, rect.y - 34, size: 12.5, color: theme.ink, align: .center, .middle)
            drawText("\(Int(sheet.width.rounded())) × \(Int(sheet.height.rounded())) mm", rect.center.x, rect.y - 16,
                     size: 12, color: theme.muted, align: .center, .middle)
            drawText("drawn \(Int(drawnW.rounded())) × \(Int(drawnH.rounded())) mm", rect.center.x, floor + 16,
                     size: 13, color: theme.ink, align: .center, .middle)
            drawText(plan.flag, rect.center.x, floor + 36, size: 12, color: theme.muted, align: .center, .middle)
            x += w + 28
        }

        diagramCaption("a sheet does the arithmetic: the drawing fits inside it, margin clear",
                       at: 366, theme: theme)
        drawText("a canvas taller than the sheet's shape scales down to its height, comes out narrower, and keeps the margin corner as its origin",
                 width / 2, 396, size: 13, color: theme.muted, align: .center, .top)
        drawText("PaperSize: .a0 to .a6, .usLetter, .usLegal, .usTabloid, any of them .landscape, or PaperSize(width:height:)",
                 width / 2, 418, size: 13, color: theme.muted, align: .center, .top)
    }

    /// The line work: a rose curve filling the canvas's width, and a second
    /// one under it when the canvas is tall enough to hold two.
    private func drawing(in canvas: Rectangle) -> [Contour] {
        var contours: [Contour] = []
        let r = canvas.width * 0.42
        let count = canvas.height > canvas.width * 1.5 ? 2 : 1
        for k in 0..<count {
            let c = Vector2(canvas.width / 2, canvas.height / Double(count) * (Double(k) + 0.5))
            var points: [Vector2] = []
            for i in 0...720 {
                let a = Double(i) / 720 * .tau * 2
                let rose = cos(3.5 * a)
                points.append(c + Vector2(cos(a), sin(a)) * (r * rose))
            }
            contours.append(Contour(points, closed: true))
        }
        return contours
    }

    private func corners(of r: Rectangle) -> [Vector2] {
        [Vector2(r.x, r.y), Vector2(r.x + r.width, r.y),
         Vector2(r.x + r.width, r.y + r.height), Vector2(r.x, r.y + r.height)]
    }
}
