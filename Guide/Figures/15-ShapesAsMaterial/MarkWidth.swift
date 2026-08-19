// figure: frame=0
//
// Guide diagram (Chapter 15): the same curve drawn three ways at one
// strokeWeight. A uniform line, a taper that swells in the middle and
// vanishes at both ends, and a flat nib that thickens across its edge and
// thins along it. Only the profile changes.
import Ollin

final class MarkWidth: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        let titles = ["one width", ".taper()", ".nib(angle:)"]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 56, width: 230, height: 196)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            withState {
                stroke(ink)
                strokeWeight(17)
                strokeCap(.round)
                switch i {
                case 0: noStrokeProfile()
                case 1: strokeProfile(.taper())
                default: strokeProfile(.nib(angle: -.pi / 5))
                }
                drawPolyline(curve(in: r))
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.corner.y + r.height + 18)
        }
    }

    /// An S-curve that heads in a wide range of directions, so the nib has
    /// something to thicken and thin against.
    func curve(in r: Rectangle) -> [Vector2] {
        (0 ... 140).map { i in
            let t = Double(i) / 140
            return Vector2(r.corner.x + 28 + t * (r.width - 56),
                           r.center.y + sin(t * .tau * 0.85 + 0.6) * (r.height * 0.31))
        }
    }
}
