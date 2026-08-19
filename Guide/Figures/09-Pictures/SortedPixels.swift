// figure: frame=0
//
// Guide diagram (Chapter 9): pixel sorting. The chapter's sunset, and the
// same picture with each column's mid-tone runs reordered by brightness.
// The sun and the horizon survive because they fall outside the threshold,
// which is what keeps the picture readable while the rest smears.
import Ollin

final class SortedPixels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    var source: Image?
    var sorted: Image?

    override func setup() {
        noiseSeed(3)
        let picture = makeSunset(size: 300)
        source = picture
        sorted = picture.pixelSorted(.vertical, by: .brightness,
                                     threshold: 0.2 ... 0.7, reversed: true)
    }

    override func draw() {
        background(paper)
        guard let source, let sorted else { return }

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        drawImage(source, in: left)
        drawImage(sorted, in: right)

        frame(left, title: "the picture")
        frame(right, title: "columns sorted by brightness")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a threshold picks which runs move, and the rest holds still",
                 width / 2, 396)
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

    /// The chapter's authored sunset, so every treatment reads the same image.
    func makeSunset(size: Int) -> Image {
        let image = Image(width: size, height: size)
        let sky = Ramp([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                        Color(hex: 0xE56B6F), Color(hex: 0xFFB703)])
        let horizon = 0.62
        let sunX = 0.58, sunY = 0.47
        for py in 0..<size {
            for px in 0..<size {
                let u = Double(px) / Double(size - 1)
                let v = Double(py) / Double(size - 1)
                var color: Color
                if v < horizon {
                    color = sky.color(at: v / horizon)
                    let d = ((u - sunX) * (u - sunX) + (v - sunY) * (v - sunY)).squareRoot()
                    let disk = 1 - smoothstep(0.075, 0.095, d)
                    let glow = (1 - smoothstep(0.04, 0.4, d)) * 0.5
                    color = Color.mix(color, Color(hex: 0xFFF3D6), t: min(1, disk + glow))
                } else {
                    let w = (v - horizon) / (1 - horizon)
                    let reflected = sky.color(at: max(0, 0.92 - w * 0.9))
                    let dark = Color.mix(reflected, Color(hex: 0x0B1020), t: 0.45 + w * 0.4)
                    let streak = noise(u * 5, v * 120)
                    let path = 1 - smoothstep(0.02, 0.16 + w * 0.3, abs(u - sunX))
                    color = Color.mix(dark, Color(hex: 0xFFD98A),
                                      t: min(1, path * (0.2 + streak * 0.8)))
                }
                image[px, py] = color
            }
        }
        return image
    }
}
