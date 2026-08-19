// figure: frame=1500 unstable
//
// Guide diagram (Chapter 20): one contest, three ages. All three panels open from
// the same seed, so they hold the same six recipes shared out the same way, and
// they are started at different frames, so at the moment this renders they are
// three ages of one contest rather than three unrelated worlds. The bar under each
// is who is left, so the picture and the tally cannot disagree.
//
// Marked unstable for the reason the other GPU sims here are: the neighbor sort
// settles ties with a race between threads, so a render is never bit-identical.
import Ollin

final class SwarmChemistryFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)
    let paper = Color(hex: 0x0B0D12)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 320)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 320)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 320)

    // Started at these frames, so the leftmost has barely begun trading recipes
    // when the rightmost has been at it for a thousand steps.
    let starts = [1430, 1100, 0]

    var runs: [SwarmChemistry] = []
    var tallies: [[Int]] = [[], [], []]

    override func setup() {
        background(paper)
        noClear()
        for panel in [left, middle, right] {
            let run = SwarmChemistry(count: 1400, bounds: panel, kinds: 6, size: 2.0,
                                     seed: 31)
            run.opacity = 0.95
            runs.append(run)
        }
    }

    override func draw() {
        background(paper)
        for (i, run) in runs.enumerated() where frameCount >= starts[i] {
            updateSwarmChemistry(run)
            drawParticles(run)
        }
        // Reading the tally stalls on the GPU, so take it once, at the end.
        if frameCount >= 1499 {
            for (i, run) in runs.enumerated() { tallies[i] = run.lineageCounts() }
        }

        for (i, panel) in [left, middle, right].enumerated() {
            let age = max(frameCount - starts[i], 0)
            frame(panel, title: "\(age) steps in")
            drawTally(tallies[i], under: panel)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a rule that spreads by winning arguments", width / 2, 470)
    }

    /// Who is left, as one stacked bar: a band per surviving line, in line order,
    /// as wide as the share it holds.
    func drawTally(_ counts: [Int], under r: Rectangle) {
        guard !counts.isEmpty else { return }
        let total = Double(max(counts.reduce(0, +), 1))
        var x = r.x
        let y = r.y + r.height + 12.0
        noStroke()
        for (line, held) in counts.enumerated() where held > 0 {
            let w = r.width * Double(held) / total
            fill(Color(hue: Double(line) / Double(counts.count), saturation: 0.55, brightness: 0.95))
            drawRect(x, y, w, 9)
            x += w
        }
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
