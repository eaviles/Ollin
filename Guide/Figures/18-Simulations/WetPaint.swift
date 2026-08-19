// figure: frame=520
//
// Guide diagram (Chapter 18): the watercolor wash simulation. A scripted
// painting: an ultramarine wash whose edge darkens as it sits, rose charged
// into it wet-in-wet, the sheet blotted and bloomed with a held water drop
// (the backrun), then dried and glazed with a yellow band that mixes
// optically where it crosses.
import Ollin

final class WetPaint: Sketch {
    var paint: WatercolorField?

    override func draw() {
        if paint == nil {
            paint = watercolor(pigments: [.frenchUltramarine, .quinacridoneRose, .hansaYellow])
        }
        guard let paint else { return }

        withField(paint) {
            noStroke()
            switch frameCount {
            case 1:
                brushLine(from: Vector2(220, 400), to: Vector2(860, 440), radius: 80,
                          color: paint.ink(0, load: 0.5))
            case 80:
                brushLine(from: Vector2(370, 420), to: Vector2(690, 450), radius: 36,
                          color: paint.ink(1, load: 0.6, water: 0.6))
            case 200:
                paint.blot()
            case 210 ... 260:
                fill(paint.water(0.8))
                drawCircle(520, 410, 44)
            case 400:
                paint.dry()
            case 410:
                brushLine(from: Vector2(470, 150), to: Vector2(520, 930), radius: 56,
                          color: paint.ink(2, load: 0.35))
            default: break
            }
        }
        drawImage(paint.image, 0, 0)
    }

    private func brushLine(from a: Vector2, to b: Vector2, radius: Double, color: Color) {
        fill(color)
        let steps = max(1, Int(a.distance(to: b) / (radius * 0.35)))
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let p = a.lerp(to: b, t) + Vector2(0, sin(t * .tau * 1.4) * radius * 0.2)
            drawCircle(p.x, p.y, radius)
        }
    }
}
