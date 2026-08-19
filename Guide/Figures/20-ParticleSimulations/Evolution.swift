// figure: frame=1450 unstable
//
// Guide diagram (Chapter 20): the same search at three ages. Each panel is its
// own population flying from the bottom to the ring at the top, past a wall with
// a gap off to one side. The panels are started at different frames, so at the
// moment this renders they are a different number of generations in; each label
// is read from the run itself, so it cannot disagree with its picture.
import Ollin

final class EvolutionFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)
    let paper = Color(hex: 0x0B0D12)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    // Started at these frames, so the leftmost is barely under way when the
    // rightmost has been breeding for a few hundred generations' worth of frames.
    let starts = [1380, 950, 0]

    var runs: [Evolution] = []
    var walls: [[Rectangle]] = []

    override func setup() {
        background(paper)
        noClear()
        for (i, panel) in [left, middle, right].enumerated() {
            let bars = [Rectangle(x: panel.x, y: panel.y + 196, width: 168, height: 13),
                        Rectangle(x: panel.x + 203, y: panel.y + 196, width: 50, height: 13)]
            let run = evolution(count: 3000, genes: 20,
                                from: Vector2(panel.x + panel.width / 2, panel.y + panel.height - 22),
                                to: Vector2(panel.x + panel.width / 2, panel.y + 34),
                                seed: UInt64(11 + i))
            run.obstacles = bars
            run.targetRadius = 20
            // A short trial with a proportionally quick flight, so a figure can
            // watch twenty generations without rendering ten thousand frames.
            run.maxSpeed = 430
            run.trialDuration = 1.0
            run.size = 1.3
            run.opacity = 0.32
            runs.append(run)
            walls.append(bars)
        }
    }

    override func draw() {
        // Fade rather than wipe, so a flight leaves the route it took. Thin,
        // because a whole flight takes most of a second and a heavier sheet would
        // erase the first half of a path before the second half was drawn.
        blendMode(.normal)
        noStroke()
        fill(Color(hex: 0x0B0D12, alpha: 0.055))
        drawRect(0, 0, width, height)

        blendMode(.add)
        for (i, run) in runs.enumerated() where frameCount >= starts[i] {
            updateEvolution(run)
            drawParticles(run)
        }
        blendMode(.normal)

        // The panels share one canvas, so mask everything outside them.
        fill(paper)
        drawRect(0, 0, width, left.y)
        drawRect(0, left.y + left.height, width, height - left.y - left.height)
        drawRect(0, left.y, left.x, left.height)
        drawRect(left.x + left.width, left.y, middle.x - left.x - left.width, left.height)
        drawRect(middle.x + middle.width, left.y, right.x - middle.x - middle.width, left.height)
        drawRect(right.x + right.width, left.y, width - right.x - right.width, left.height)

        for (i, panel) in [left, middle, right].enumerated() {
            noStroke()
            fill(Color(hex: 0xF7F5F1, alpha: 0.30))
            for bar in walls[i] { drawRect(bar) }
            noFill()
            stroke(Color(hex: 0xF2C14E, alpha: 0.75))
            strokeWeight(1.5)
            drawCircle(center: runs[i].target, radius: runs[i].targetRadius)
            frame(panel, title: "generation \(runs[i].generation)")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("nobody wrote down the route", width / 2, 462)
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
        drawText(title, r.x + 2, r.y - 20)
    }
}
