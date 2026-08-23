// figure: frame=0
//
// Guide diagram: six view boxes on one canvas, each running the same piece
// under a different seed. Each box has its own background, its own coordinates,
// and its own clip, and none of them knows it is not the whole window. The boxes
// are given the canvas's own shape, since that is what the code inside believes
// it has.
import Ollin

final class ViewBoxSheet: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)

    static let palettes: [(Color, Color)] = [
        (Color(hex: 0xF6E7D8), Color(hex: 0xC1553C)),
        (Color(hex: 0xE7EDF2), Color(hex: 0x2F5D7C)),
        (Color(hex: 0xEDE9F2), Color(hex: 0x59417E)),
        (Color(hex: 0xF3EFE0), Color(hex: 0x6B7A3A)),
        (Color(hex: 0xF7E9E9), Color(hex: 0xA33B52)),
        (Color(hex: 0xE6EEEA), Color(hex: 0x2C6B5B)),
    ]

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        // The boxes take the canvas's own shape, so nothing is letterboxed.
        let boxWidth = 250.0, boxHeight = boxWidth * height / width
        for seed in 0..<6 {
            let frame = Rectangle(x: 25 + Double(seed % 3) * (boxWidth + 40),
                                  y: 46 + Double(seed / 3) * (boxHeight + 74),
                                  width: boxWidth, height: boxHeight)
            withViewBox(frame) { petals(seed: seed) }
            noStroke()
            fill(faint)
            textSize(18)
            textAlign(.center, .top)
            drawText("seed \(seed)", frame.center.x, frame.y + frame.height + 12)
        }
        fill(faint)
        textSize(17)
        textAlign(.center, .top)
        drawText("one piece, six seeds, six boxes, one canvas", 440, 516)
    }

    /// Written as though it owned the window: it reads `width`, `height` and
    /// `center`, and wipes its own background.
    func petals(seed: Int) {
        randomSeed(seed)
        let (wash, mark) = ViewBoxSheet.palettes[seed % ViewBoxSheet.palettes.count]
        background(wash)
        let count = 5 + seed % 6
        withState {
            translate(center)
            for i in 0..<count {
                withState {
                    rotate(Double(i) / Double(count) * .tau)
                    let length = height * (0.22 + random(0.16))
                    let waist = width * (0.05 + random(0.05))
                    noStroke()
                    fill(mark.withAlpha(0.55))
                    drawShape { path in
                        path.move(to: Vector2(0, 0))
                        path.cubicCurve(to: Vector2(0, -length),
                                        control1: Vector2(waist, -length * 0.25),
                                        control2: Vector2(waist * 0.6, -length * 0.85))
                        path.cubicCurve(to: Vector2(0, 0),
                                        control1: Vector2(-waist * 0.6, -length * 0.85),
                                        control2: Vector2(-waist, -length * 0.25))
                        path.close()
                    }
                    fill(mark)
                    drawCircle(0, -length, waist * 0.35)
                }
            }
        }
    }
}
