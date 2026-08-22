// figure: frame=0
//
// Guide figure (Chapter 16): diffusion curves. The marks on their own, the field
// they settle into, and what one more curve does to it.
import Ollin

final class Diffusion: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    let dusk = Color(hex: 0xE86F4A)
    let deep = Color(hex: 0x101A2E)
    let sand = Color(hex: 0xE8C98A)
    let sky = Color(hex: 0x2A3D66)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["the marks", "let out", "one more curve"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            let marks = renderTarget(width: Int(tile), height: Int(tile))
            withTarget(marks) {
                background(Color(white: 0, alpha: 0))
                let horizon = stride(from: -10.0, through: tile + 10, by: 8).map { t in
                    Vector2(t, tile * 0.42 + sin(t / tile * 5) * tile * 0.05)
                }
                drawDiffusionCurve(horizon, left: dusk, right: deep, width: 3)
                noStroke()
                fill(Color(hex: 0xFFE9B0))
                drawCircle(tile * 0.68, tile * 0.2, 16)
                fill(sky)
                drawCircle(tile * 0.08, tile * 0.08, 12)

                if index == 2 {
                    let ridge = stride(from: -10.0, through: tile + 10, by: 8).map { t in
                        Vector2(t, tile * 0.76 - sin(t / tile * 3) * tile * 0.06)
                    }
                    drawDiffusionCurve(ridge, left: sand, right: sky, width: 3)
                }
            }

            noStroke()
            fill(Color(white: 0.06))
            drawRect(frame)
            if index == 0 {
                drawImage(marks.image, in: frame)
            } else {
                drawImage(marks.filtered(.diffuse(sharpness: 1)).image, in: frame)
            }

            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
