// figure: frame=0 themed
//
// Guide figure (Chapter 15): circle packing as a time lapse. The same seeded
// packer at four moments: big circles claim the open space first, and every
// later circle grows until it touches whatever is already there.
import Ollin

final class PackingLapse: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    let steps = [2, 8, 30, 220]
    var stages: [[Circle]] = []

    override func setup() {
        stages = []
        for (i, count) in steps.enumerated() {
            let r = panelRect(i)
            let packer = ContinuousPacking(in: r.inset(by: .all(8)), seed: 3,
                                           minRadius: 3, maxRadius: 60,
                                           padding: 2, attemptsPerStep: 6)
            packer.step(count)
            stages.append(packer.circles)
        }
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 40 + Double(i) * 206, y: 55, width: 190, height: 190)
    }

    override func draw() {
        background(paper)
        textSize(17)

        for (i, circles) in stages.enumerated() {
            let r = panelRect(i)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)
            stroke(ink)
            strokeWeight(1.6)
            drawCircles(circles)
            noStroke()
            fill(faint)
            textAlign(.center, .top)
            drawText("step \(steps[i])", r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every circle grows until it touches what got there first", width / 2, 288)
    }
}
