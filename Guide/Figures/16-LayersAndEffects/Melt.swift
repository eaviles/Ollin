// figure: frame=0
//
// Guide diagram (Chapter 16): the luminance melt. A simple painted scene
// drawn into a layer, then the same layer filtered. One displacement field
// both warps the noise the filter draws with and shifts where it samples the
// picture, which is why the result reads as dyed rather than only smeared.
import Ollin

final class Melt: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        let scene = renderTarget(scale: 0.5)
        withTarget(scene) { paint() }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.melt(phase: 2.4)).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.melt())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("brightness decides where the picture runs",
                 width / 2, 396)
    }

    /// A dusk scene: a graded sky, a low sun, and a dark headland.
    func paint() {
        let sky = Ramp([Color(hex: 0x1B2A4A), Color(hex: 0x6A4E7C),
                        Color(hex: 0xE07A5F), Color(hex: 0xF2CC8F)])
        noStroke()
        for i in 0 ..< 90 {
            let t = Double(i) / 89
            fill(sky.color(at: t))
            drawRect(0, t * height, width, height / 89 + 1)
        }
        fill(Color(hex: 0xFFF3D6))
        drawCircle(width * 0.62, height * 0.58, width * 0.11)
        fill(Color(hex: 0x14202E))
        drawPolygon([Vector2(0, height * 0.74), Vector2(width * 0.34, height * 0.6),
                     Vector2(width * 0.7, height * 0.78), Vector2(width, height * 0.68),
                     Vector2(width, height), Vector2(0, height)])
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
