// figure: frame=0
//
// Guide diagram (Chapter 12): crack growth. Left, the rule: a crack runs
// straight until it meets another line, then it stops and a new crack sets
// out perpendicular from the pattern. Right, what that builds after a few
// thousand ticks: the plane subdivided into city blocks, each crack washing
// the open space on one side of its line.
import Ollin

final class CrackedCity: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)
    let inks = [Color(hex: 0x1F5673), Color(hex: 0xC26D3F),
                Color(hex: 0x8A9B68), Color(hex: 0x71486E)]

    var marks: [CrackGrowth.Mark] = []

    override func setup() {
        let right = panel(1)
        let field = CrackGrowth(width: right.width, height: right.height,
                                cracks: 3, seedAngles: 12, maxCracks: 32, seed: 5)
        marks = field.step(800)
    }

    func panel(_ i: Int) -> Rectangle {
        Rectangle(x: 50 + Double(i) * 420, y: 60, width: 370, height: 340)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        // Left: the rule.
        let left = panel(0)
        frame(left, title: "a crack runs until it meets a line")
        let floor = Vector2(left.x + 40, left.y + 230)
        stroke(ink)
        strokeWeight(2.5)
        drawLine(floor, floor + Vector2(290, 0))
        // The arriving crack, stopped on the line.
        let hit = floor + Vector2(200, 0)
        drawLine(hit + Vector2(0, -150), hit)
        noStroke()
        fill(accent)
        drawCircle(center: hit, radius: 6)
        label("stops here", hit + Vector2(0, 26), color: accent)
        // The child it recruits, perpendicular off the pattern.
        let parent = hit + Vector2(0, -90)
        stroke(accent)
        strokeWeight(2)
        drawLine(parent, parent + Vector2(70, 0))
        drawLine(parent + Vector2(70, 0), parent + Vector2(62, -6))
        drawLine(parent + Vector2(70, 0), parent + Vector2(62, 6))
        label("a new crack sets out,", parent + Vector2(52, -34), color: accent)
        label("perpendicular", parent + Vector2(52, -16), color: accent)

        // Right: what that builds.
        let right = panel(1)
        frame(right, title: "eight hundred ticks later")
        withState {
            translate(right.x, right.y)
            noStroke()
            for mark in marks {
                let ink = inks[mark.crack % inks.count]
                for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
                                                gain: mark.gain, count: 12) {
                    fill(ink.withAlpha(grain.alpha))
                    drawPoint(grain.position)
                }
                fill(self.ink.withAlpha(0.33))
                drawPoint(mark.point)
            }
        }

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every stop is a birth, so the map only gets busier", width / 2, 428)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
