// figure: frame=700 unstable
//
// Guide diagram (Chapter 20): one model, three settings. Each panel runs the same
// three lines of Particle Lenia and differs only in what crowding the growth
// function is asking for and how fussy it is about getting it. The point of the
// picture is that those two numbers, not the code, are what decides whether you
// get a solid body, a loose colony, or a shell.
//
// Marked unstable for the reason the other GPU sims here are: the neighbor sort
// settles ties with a race between threads, so a render is never bit-identical.
import Ollin

final class ParticleLeniaFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)
    let paper = Color(hex: 0x0B0D12)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    // What each panel asks of the growth term: the crowding it prefers, and how
    // narrowly. Everything else is identical.
    let settings: [(muG: Double, sigmaG: Double, label: String)] = [
        (0.6, 0.15, "prefers 0.6, fussy"),
        (1.1, 0.15, "prefers 1.1"),
        (0.6, 0.05, "prefers 0.6, fussier"),
    ]

    var runs: [ParticleLenia] = []

    override func setup() {
        background(paper)
        noClear()
        for (i, panel) in [left, middle, right].enumerated() {
            let run = ParticleLenia(count: 1700, bounds: panel, spacing: 3.4,
                                    seed: 21 + i)
            run.muG = settings[i].muG
            run.sigmaG = settings[i].sigmaG
            // One published step a frame, which is the unit the model's behavior is
            // described in. At the default pace a frame is a sixth of one and the
            // figure would render a population that had barely moved.
            run.speed = run.maxStep * 60
            run.size = 2.0
            run.opacity = 0.9
            runs.append(run)
        }
    }

    override func draw() {
        background(paper)
        blendMode(.add)
        for run in runs {
            updateParticleLenia(run)
            drawParticles(run)
        }
        blendMode(.normal)

        for (i, panel) in [left, middle, right].enumerated() {
            frame(panel, title: settings[i].label)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("two numbers decide what kind of thing this is", width / 2, 462)
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
