// figure: frame=0 themed
//
// Guide diagram (Chapter 29): a wavetable is a row of cycles read by
// position, and a note reads each one at the strength its pitch allows. The
// top panel stacks the four frames of the plain table with the cycle at one
// position drawn between them in the accent, the blend of the two it lands
// between. The bottom panel is the sawtooth frame three times, with every
// harmonic, with sixteen, and with four: what a low, a middle, and a high
// note actually read, so the corner softening is visible rather than
// described. Every cycle is read from the shipped table.
import Ollin
import OllinDiagram
import OllinAudio

final class WavetableFrames: Sketch {
    override var canvasSize: CanvasSize { .size(880, 640) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    let position = 0.4

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        drawStack(panel: Rectangle(x: 150, y: 44, width: 560, height: 300))
        drawLevels(top: 400)

        diagramCaption("one table read by position, and one frame as three pitches read it",
                       at: 610, theme: theme)
    }

    /// The four frames stacked, faintest to brightest, and the read position
    /// between them with the cycle it blends.
    private func drawStack(panel: Rectangle) {
        let table = Wavetable.basic
        let names = ["sine", "triangle", "sawtooth", "square"]
        let rows = table.frameCount
        let lane = panel.height / Double(rows)

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("the frames of the plain table, and where a note reads", panel.x - 110, panel.y - 18)

        for index in 0..<rows {
            let middle = panel.bottomRight.y - (Double(index) + 0.5) * lane
            noFill()
            stroke(theme.ink(0.35 + 0.5 * Double(index) / Double(rows - 1)))
            strokeWeight(1.4)
            drawCycle(table.frame(index), left: panel.x, right: panel.topRight.x,
                      middle: middle, height: lane * 0.4)
            noStroke()
            fill(soft)
            textSize(12)
            textAlign(.right, .middle)
            drawText(names[index], panel.x - 16, middle)
        }

        // The position runs up the stack; the accent cycle is the blend read there.
        stroke(faint)
        strokeWeight(1)
        drawLine(panel.topRight.x + 40, panel.bottomRight.y, panel.topRight.x + 40, panel.y)
        let middle = panel.bottomRight.y - (position * Double(rows - 1) + 0.5) * lane
        noFill()
        stroke(accent)
        strokeWeight(2.4)
        drawCycle(table.cycle(at: position), left: panel.x, right: panel.topRight.x,
                  middle: middle, height: lane * 0.4)
        noStroke()
        fill(accent)
        drawCircle(panel.topRight.x + 40, middle, 5)
        fill(soft)
        textSize(12)
        textAlign(.left, .middle)
        drawText("position \(position)", panel.topRight.x + 52, middle)
        textAlign(.left, .bottom)
        drawText("1", panel.topRight.x + 48, panel.y + 4)
        textAlign(.left, .top)
        drawText("0", panel.topRight.x + 48, panel.bottomRight.y - 4)
    }

    /// The sawtooth frame as three notes read it: every harmonic, sixteen,
    /// and four.
    private func drawLevels(top: Double) {
        let table = Wavetable.basic
        let takes: [(String, Int)] = [
            ("every harmonic: a low note", Wavetable.length / 2 - 1),
            ("sixteen: a middle note", 16),
            ("four: a high note", 4),
        ]
        let panelWidth = 240.0, gap = 40.0
        let left = (880 - (panelWidth * 3 + gap * 2)) / 2
        for (index, take) in takes.enumerated() {
            let panel = Rectangle(x: left + Double(index) * (panelWidth + gap), y: top,
                                  width: panelWidth, height: 150)
            diagramFrame(panel, title: take.0, theme: theme)
            noFill()
            stroke(index == 0 ? ink : accent)
            strokeWeight(1.8)
            drawCycle(table.frame(2, harmonicsUpTo: take.1), left: panel.x + 12,
                      right: panel.topRight.x - 12, middle: panel.center.y, height: panel.height * 0.38)
        }
    }

    private func drawCycle(_ cycle: [Double], left: Double, right: Double,
                           middle: Double, height: Double) {
        let step = max(1, cycle.count / 512)
        let points = Swift.stride(from: 0, through: cycle.count, by: step).map { index in
            let value = cycle[index % cycle.count]
            return Vector2(left + (right - left) * Double(index) / Double(cycle.count),
                           middle - value * height)
        }
        drawPolyline(points)
    }
}
