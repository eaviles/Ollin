// figure: frame=0
//
// Guide figure (Chapter 15): what clipping does to bright light. Three
// additive lamps overlap; under the default clamp the hot middle saturates
// to a flat white plateau. The sibling figure renders the identical scene
// through toneMap(.aces).
import Ollin

final class ToneClamp: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    override func setup() {
        toneMap(.clamp, exposure: 2.6)
    }

    override func draw() {
        background(Color(hex: 0x05070C))

        blendMode(.add)
        noStroke()
        let lamps: [(Double, Color)] = [
            (0.3, Color(hex: 0xFFB37A)), (0.5, Color(hex: 0xA8F2C4)), (0.7, Color(hex: 0x8FA8FF)),
        ]
        for lamp in lamps {
            let c = Vector2(width * lamp.0, height * 0.5)
            fill(.radial(center: c, radius: 220, Ramp([lamp.1, lamp.1.withAlpha(0)])))
            drawCircle(center: c, radius: 220)
        }
        blendMode(.normal)

        noStroke()
        fill(Color(white: 1, alpha: 0.65))
        textSize(17)
        textAlign(.left, .bottom)
        drawText("toneMap(.clamp)  ·  the default: past full brightness, clip", 18, height - 14)
    }
}
