// figure: frame=0 themed
//
// Docs catalog figure (Drawing/Drawing.md, drawPoint): the round marker at a
// run of sizes down to a sub-pixel speck that fades by ink, and a grid of
// tiny points reading as an even wash rather than speckle.
import Ollin

final class DrawPoint: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        noStroke()

        // A size run, one call per dot; size is the diameter.
        let sizes = [28.0, 14.0, 7.0, 3.0, 1.0]
        let xs = [90.0, 165.0, 240.0, 315.0, 390.0]
        fill(ink)
        for (x, size) in zip(xs, sizes) {
            drawPoint(x, 140, size)
        }
        textSize(16)
        textAlign(.center, .top)
        for (x, size) in zip(xs, sizes) {
            drawText(size == 1 ? "1" : String(Int(size)), x, 176)
        }
        fill(accent)
        drawText("still round, fading by ink", 390, 200)

        // A field of sub-pixel points: an even wash, not speckle.
        fill(ink)
        var y = 84.0
        while y <= 204 {
            var x = 540.0
            while x <= 790 {
                drawPoint(x, y, 1.2)
                x += 6
            }
            y += 6
        }

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("size is the diameter", 240, 266)
        drawText("a field of sub-pixel points reads as a wash", 665, 266)
    }
}
