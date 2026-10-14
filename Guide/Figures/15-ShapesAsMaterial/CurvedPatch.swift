// figure: frame=0 themed
//
// Guide diagram (Chapter 15): an outline bent into a patch. Left, a word
// and a grid set flat in a rectangle. Middle, the same outlines bent into a
// patch of four straight sides between four corners, the bilinear map, so
// every grid line stays straight and only the corners have moved. Right,
// the same outlines bent into a patch whose four sides are curves, a Coons
// patch, so the word and every grid line bow with the sides. Nothing here
// uses randomness.
import Ollin
import OllinDiagram

final class CurvedPatch: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.22) }
    var accent: Color { theme.accent }

    let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    /// The flat rectangle every panel bends from, in panel coordinates.
    let flat = Rectangle(x: 10, y: 90, width: 280, height: 190)

    override func draw() {
        background(paper)
        let corners = CoonsPatch(topLeft: Vector2(30, 60), topRight: Vector2(290, 110),
                                 bottomRight: Vector2(262, 330), bottomLeft: Vector2(0, 280))
        func side(_ a: Vector2, _ b: Vector2, _ bulge: Double, _ wobble: Double) -> Contour {
            let normal = (b - a).perpendicular.normalized
            return Contour((0 ... 40).map { i -> Vector2 in
                let t = Double(i) / 40
                return a + (b - a) * t + normal * (bulge * sin(t * .pi) + wobble * sin(t * 2 * .pi))
            }, closed: false)
        }
        let tl = Vector2(10, 80), tr = Vector2(280, 70), br = Vector2(270, 320), bl = Vector2(0, 300)
        let curves = CoonsPatch(top: side(tl, tr, 34, 18), right: side(tr, br, -18, 0),
                                bottom: side(bl, br, 40, -16), left: side(tl, bl, 22, 0))
        panel(at: Vector2(30, 70), patch: CoonsPatch(flat), title: "set flat",
              note: "a word and a grid in a Rectangle", drawsSides: false)
        panel(at: Vector2(390, 70), patch: corners, title: "four corners",
              note: "CoonsPatch(topLeft:topRight:…)", drawsSides: true)
        panel(at: Vector2(750, 70), patch: curves, title: "four curves",
              note: "CoonsPatch(top:right:bottom:left:)", drawsSides: true)
    }

    func panel(at origin: Vector2, patch: CoonsPatch, title: String, note: String, drawsSides: Bool) {
        withState {
            translate(origin)
            noStroke()
            fill(ink)
            textSize(19)
            textAlign(.left, .middle)
            drawText(title, 0, -34)
            fill(ink.withAlpha(0.7))
            textSize(15)
            textAlign(.left, .top)
            drawText(note, 0, 372)

            // The grid: every line a straight line across the flat
            // rectangle, bent into the patch.
            noFill()
            stroke(soft)
            strokeWeight(1.5)
            for k in 0 ... 8 {
                let x = flat.x + flat.width * Double(k) / 8
                let line = Contour([Vector2(x, flat.y), Vector2(x, flat.y + flat.height)], closed: false)
                drawPolyline(line.warped(from: flat, into: patch, spacing: 3).points)
            }
            for k in 0 ... 6 {
                let y = flat.y + flat.height * Double(k) / 6
                let line = Contour([Vector2(flat.x, y), Vector2(flat.x + flat.width, y)], closed: false)
                drawPolyline(line.warped(from: flat, into: patch, spacing: 3).points)
            }

            // The word, set in the middle of the flat rectangle.
            textFont(face)
            textAlign(.center, .middle)
            textSize(90)
            let glyphs = textToShapes("patch", flat.center.x, flat.center.y)
            textFont(.system)
            noStroke()
            fill(ink)
            for glyph in glyphs { drawShape(glyph.warped(from: flat, into: patch, spacing: 2)) }

            // The four sides and their corners.
            if drawsSides {
                noFill()
                stroke(accent)
                strokeWeight(2.5)
                for side in [patch.top, patch.right, patch.bottom, patch.left] { drawPolyline(side.points) }
                noStroke()
                fill(accent)
                for corner in [patch.topLeft, patch.topRight, patch.bottomRight, patch.bottomLeft] {
                    drawCircle(center: corner, radius: 5)
                }
            }
        }
    }
}
