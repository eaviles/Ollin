// figure: frame=0
//
// Guide diagram (Chapter 22): a slit scan. A synthetic clip (a bar sweeping
// across a striped ground) is pushed into a frame history, then read back
// with a delay that varies across the picture, so each column shows a
// different moment. Left, the newest frame; right, the same history read
// with time running across it.
import Ollin

final class SlitScanDelay: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var newest: Image?
    var scanned: Image?

    override func setup() {
        let history = Ollin.SlitScan(frames: 48)
        for step in 0 ..< 48 {
            history.push(clipFrame(at: Double(step) / 47))
        }
        newest = clipFrame(at: 1)
        scanned = history.image(delay: { uv in uv.x })
    }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)
        if let newest { drawImage(newest, in: left) }
        if let scanned { drawImage(scanned, in: right) }

        frame(left, title: "the newest frame")
        frame(right, title: "delay running left to right")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every column is a different moment of the same clip",
                 width / 2, 396)
    }

    /// One frame of a synthetic clip: horizontal stripes scrolling downward,
    /// with one bright band sweeping down the frame. Both change everywhere
    /// at once, which is what a slit scan can actually show.
    func clipFrame(at t: Double) -> Image {
        let size = 220
        let image = Image(width: size, height: size)
        let bandY = 0.14 + t * 0.72
        for y in 0 ..< size {
            for x in 0 ..< size {
                let v = Double(y) / Double(size - 1)
                let stripe = sin((v + t * 0.55) * 30) * 0.5 + 0.5
                var color = Color.mix(Color(hex: 0x16202E), Color(hex: 0x2C4260),
                                      t: stripe)
                let band = 1 - smoothstep(0.015, 0.045, abs(v - bandY))
                color = Color.mix(color, Color(hex: 0xF2C14E), t: band)
                image[x, y] = color
            }
        }
        return image
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
