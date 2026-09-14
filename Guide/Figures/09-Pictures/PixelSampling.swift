// figure: frame=0 themed
//
// Guide diagram (Chapter 9): reading an image pixel by pixel. Left, one of
// the bundled photographs at its working size, a profile on a plain ground.
// Right, the same picture read back on a coarse grid: one dot per cell,
// colored by the pixel it landed on and sized by how bright that pixel is.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class PixelSampling: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var source: Image?

    override func setup() {
        source = SamplePhoto.profile.load().resized(width: 160, height: 160)
    }

    override func draw() {
        background(paper)
        guard let source else { return }

        let left = Rectangle(x: 85, y: 90, width: 320, height: 320)
        let right = Rectangle(x: 475, y: 90, width: 320, height: 320)

        // The image itself.
        drawImage(source, in: left)
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(left)

        // The same image, sampled: a dot per cell.
        noStroke()
        fill(Color(hex: 0x101319))
        drawRect(right)
        let cells = 32
        let cell = right.width / Double(cells)
        for row in 0..<cells {
            for col in 0..<cells {
                let u = (Double(col) + 0.5) / Double(cells)
                let v = (Double(row) + 0.5) / Double(cells)
                let c = source[Int(u * Double(source.width - 1)),
                               Int(v * Double(source.height - 1))]
                let brightness = c.red * 0.2126 + c.green * 0.7152 + c.blue * 0.0722
                fill(c)
                drawCircle(right.x + (Double(col) + 0.5) * cell,
                           right.y + (Double(row) + 0.5) * cell,
                           cell * 0.5 * (0.2 + 0.8 * brightness))
            }
        }

        noStroke()
        fill(faint)
        textAlign(.center, .middle)
        textSize(17)
        drawText("the image: stored colors", left.x + left.width / 2, 442)
        drawText("one dot per cell, sized by brightness", right.x + right.width / 2, 442)

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("sample the picture, then let each pixel drive a mark", width / 2, 490)
    }
}
