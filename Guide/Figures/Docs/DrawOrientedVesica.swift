// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawOrientedVesica): the lens is
// placed by its two tip points, so the figure marks both tips on each
// variant; the waist width runs from a sliver up to the tip distance, where
// the lens closes into a circle.
import Ollin

final class DrawOrientedVesica: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(a: Vector2(96, 196), b: Vector2(266, 104), width: 90,
              label: "width 90, a lens", labelX: 181)
        panel(a: Vector2(372, 196), b: Vector2(542, 104), width: 34,
              label: "width 34, a sliver", labelX: 457)
        let a = Vector2(652, 196), b = Vector2(802, 104)
        panel(a: a, b: b, width: a.distance(to: b),
              label: "width = tip distance, a circle", labelX: 727)
    }

    func panel(a: Vector2, b: Vector2, width lens: Double,
               label: String, labelX: Double) {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawOrientedVesica(a, b, width: lens)

        noStroke()
        fill(accent)
        drawCircle(center: a, radius: 3.5)
        drawCircle(center: b, radius: 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(label, labelX, 252)
    }
}
