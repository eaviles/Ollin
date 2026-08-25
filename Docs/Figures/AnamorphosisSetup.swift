// figure: frame=0 themed
//
// Docs diagram (Drawing/Anamorphosis.md): the setup seen from above. The
// mirrored cylinder stands on the page, the picture wraps its near face at
// true size, and the plate's marks land between the glass and the eye,
// spreading as they go; on its own the plate reads as nothing.
import Ollin
import OllinDiagram

final class AnamorphosisSetup: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.28) }
    var faint: Color { theme.ink(0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEE8C42 : 0xE07A2F) }

    let mirrorX = 430.0, mirrorY = 205.0, mirrorR = 85.0
    let eyeX = 430.0, eyeY = 492.0

    override func draw() {
        background(paper)

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(19)
        textAlign(.left, .top)
        drawText("the page, seen from above", 48, 34)

        // Sight lines from the eye to the near face of the glass, and the
        // plate's marks landing on them partway out, wider toward the edges.
        for t in -2...2 {
            let angle = Double.pi / 2 + Double(t) * 0.34
            let px = mirrorX + mirrorR * cos(angle)
            let py = mirrorY + mirrorR * sin(angle)
            stroke(soft)
            strokeWeight(1.5)
            drawLine(eyeX, eyeY, px, py)

            let s = 0.42 + Double(abs(t)) * 0.06
            let mx = px + (eyeX - px) * s
            let my = py + (eyeY - py) * s
            let dx = eyeX - px, dy = eyeY - py
            let len = (dx * dx + dy * dy).squareRoot()
            let nx = -dy / len, ny = dx / len
            let half = 14.0 + Double(abs(t)) * 7
            stroke(accent)
            strokeWeight(7)
            strokeCap(.round)
            drawLine(mx - nx * half, my - ny * half, mx + nx * half, my + ny * half)
        }

        // The mirror itself, with the picture wrapped on its near face.
        noFill()
        stroke(ink)
        strokeWeight(3)
        drawCircle(mirrorX, mirrorY, mirrorR)

        var band: [Vector2] = []
        for i in 0...48 {
            let angle = Double.pi / 2 - 0.85 + Double(i) / 48 * 1.7
            band.append(Vector2(mirrorX + mirrorR * cos(angle),
                                mirrorY + mirrorR * sin(angle)))
        }
        stroke(accent)
        strokeWeight(7)
        drawPolyline(band.map { $0 })

        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .middle)
        drawText("mirror", mirrorX, mirrorY - 8)

        // The eye.
        fill(ink)
        drawCircle(eyeX, eyeY, 6)
        textAlign(.left, .middle)
        drawText("eye", eyeX + 20, eyeY)

        // Callouts.
        stroke(soft)
        strokeWeight(1.5)
        drawLine(612, 262, 505, 262)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText("the picture, wrapped on the", 622, 252)
        drawText("near face at true size", 622, 276)

        stroke(soft)
        strokeWeight(1.5)
        drawLine(310, 372, 356, 380)
        noStroke()
        fill(ink)
        textAlign(.right, .middle)
        drawText("the plate: marks between the", 300, 348)
        drawText("glass and the eye, spreading", 300, 372)
        drawText("as they go, unreadable alone", 300, 396)
    }
}
