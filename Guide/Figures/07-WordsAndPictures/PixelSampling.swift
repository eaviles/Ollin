// figure: frame=0
//
// Guide diagram (Chapter 7): reading an image pixel by pixel. Left, a small
// image authored in code (a sunset over water). Right, the same image read
// back on a coarse grid: one dot per cell, colored by the pixel it landed on
// and sized by how bright that pixel is.
import Ollin

final class PixelSampling: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    var source: Image?

    override func setup() {
        noiseSeed(3)
        source = makeSunset(size: 160)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
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
        let cells = 24
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
