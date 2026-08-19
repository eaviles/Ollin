// figure: frame=0
//
// Guide diagram (Chapter 15): three filters that want particular food. The
// same noise layer lit as a physical surface, screened into exactly two
// colors, and warped around a point that is not the middle.
import Ollin

final class SpecialFilters: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 62, width: 262, height: 262)
        }

        // One layer, three treatments.
        let source = renderTarget(scale: 0.5)
        withTarget(source) {
            drawImage(generate(.noise(scale: 3.4, warp: 0.6)).image, 0, 0)
        }

        drawImage(source.filtered(.relight(.metal, angle: -.pi * 0.7,
                                           elevation: 0.55, height: 4,
                                           intensity: 1.2,
                                           color: Color(hex: 0xC9A227))).image,
                  in: panels[0])

        drawImage(source.filtered(.dither(dark: Color(hex: 0x1B2A4A),
                                          light: Color(hex: 0xF2CC8F),
                                          pixelSize: 3)).image,
                  in: panels[1])

        // The warp centers on a point given in 0…1 layer coordinates, so it
        // does not have to be the middle of the picture.
        drawImage(source.filtered(.swirl(angle: 4.2, radius: 0.42,
                                         center: Vector2(0.3, 0.34))).image,
                  in: panels[2])
        noFill()
        stroke(Color(hex: 0xE4572E))
        strokeWeight(2)
        drawCircle(center: panels[2].point(u: 0.3, v: 0.34), radius: 7)

        let titles = [".relight(.metal)", ".dither(dark:light:)",
                      ".swirl(center:)"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one noise layer, read as a surface, as tone, and as a map",
                 width / 2, 348)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
