// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawUnevenCapsule): the tapered
// capsule between its two marked endpoints, and the equal-radii case, which
// is the plain capsule.
import Ollin

final class DrawUnevenCapsule: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        panel(a: Vector2(116, 148), b: Vector2(368, 148), ra: 58, rb: 16,
              labelX: 242, name: "ra 58 at a, rb 16 at b")
        panel(a: Vector2(536, 148), b: Vector2(788, 148), ra: 38, rb: 38,
              labelX: 662, name: "equal radii: a plain capsule")
    }

    func panel(a: Vector2, b: Vector2, ra: Double, rb: Double,
               labelX: Double, name: String) {
        fill(wash)
        stroke(ink)
        strokeWeight(3)
        drawUnevenCapsule(a, b, ra, rb)

        noStroke()
        fill(accent)
        drawCircle(center: a, radius: 3.5)
        drawCircle(center: b, radius: 3.5)

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(name, labelX, 262)
    }
}
