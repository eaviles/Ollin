// figure: frame=0 themed
//
// Guide figure (Chapter 12): a Kuramoto crowd falling into step. Left, one
// crowd of three hundred at three moments, the pull three times what it needs:
// the phases as dots on a wheel, scattered, gathering, bunched, with the order
// parameter drawn as an arrow from the center that grows with them. Right, the
// coherence over twelve seconds for a pull at half the critical coupling, at
// it, and at three times it: the first never rises, the last climbs to one.
// Every crowd shares one seed, so the three curves start from the same phases.
import Foundation
import Ollin
import OllinDiagram

final class Fireflies: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    private let count = 300
    private let seconds = 12.0
    private let multiples = [0.5, 1.0, 3.0]
    private let moments = [0.0, 2.0, 8.0]

    /// The coherence per frame for each multiple of the critical coupling.
    private var curves: [[Double]] = []
    /// The phases of the strongly coupled crowd at each moment, with r and psi.
    private var wheels: [(phases: [Double], r: Double, psi: Double)] = []
    private var critical = 0.0

    override func setup() {
        var curves: [[Double]] = []
        var wheels: [(phases: [Double], r: Double, psi: Double)] = []
        for multiple in multiples {
            let crowd = Kuramoto(count: count, spread: 0.5, seed: 3)
            crowd.coupling = multiple * crowd.criticalCoupling
            critical = crowd.criticalCoupling
            var curve: [Double] = []
            for frame in 0 ... Int(seconds * 60) {
                let t = Double(frame) / 60
                if multiple == multiples.last, moments.contains(t) {
                    wheels.append((crowd.phases, crowd.coherence, crowd.meanPhase))
                }
                curve.append(crowd.coherence)
                crowd.advance()
            }
            curves.append(curve)
        }
        self.curves = curves
        self.wheels = wheels
    }

    override func draw() {
        background(theme.paper)
        textSize(15)

        // The wheels: one per moment, in a row on the left.
        for (i, wheel) in wheels.enumerated() {
            let c = Vector2(100 + Double(i) * 130, 150)
            let r = 52.0
            noFill()
            stroke(theme.ink(0.25))
            strokeWeight(1.5)
            drawCircle(center: c, radius: r)
            noStroke()
            fill(theme.ink(0.55))
            for phase in wheel.phases {
                drawCircle(c.x + cos(phase) * r, c.y + sin(phase) * r, 2.2)
            }
            let tip = Vector2(c.x + cos(wheel.psi) * r * wheel.r, c.y + sin(wheel.psi) * r * wheel.r)
            stroke(theme.accent)
            strokeWeight(3)
            strokeCap(.round)
            drawLine(c, tip)
            noStroke()
            fill(theme.accent)
            drawCircle(center: tip, radius: 4.5)
            fill(theme.ink)
            textAlign(.center, .top)
            drawText("\(Int(moments[i])) s", c.x, c.y + r + 14)
            fill(theme.muted)
            textSize(13)
            drawText("r = " + String(format: "%.2f", wheel.r), c.x, c.y + r + 34)
            textSize(15)
        }
        noStroke()
        fill(theme.ink)
        textAlign(.center, .top)
        drawText("one crowd, three times the critical coupling", 230, 42)

        // The chart: coherence over time for the three pulls.
        let chart = Rectangle(x: 470, y: 60, width: 370, height: 220)
        diagramFrame(chart, title: nil, theme: theme)
        let labels = ["half the critical coupling", "at the critical coupling", "three times the critical coupling"]
        let colors = [theme.ink(0.35), theme.ink, theme.accent]
        noFill()
        strokeWeight(2)
        for (k, curve) in curves.enumerated() {
            stroke(colors[k])
            let points = curve.enumerated().map { frame, r -> Vector2 in
                Vector2(chart.x + Double(frame) / Double(curve.count - 1) * chart.width,
                        chart.y + chart.height - r * chart.height)
            }
            drawPolyline(points)
        }
        // A legend in the empty middle right, above the two low curves and below
        // the locked one, a dash in each curve's color before its words.
        textSize(13)
        for (row, k) in [2, 1, 0].enumerated() {
            let y = chart.y + chart.height - 100 + Double(row) * 20
            let x = chart.x + 130
            stroke(colors[k])
            strokeWeight(3)
            strokeCap(.round)
            drawLine(x, y, x + 16, y)
            noStroke()
            fill(colors[k])
            textAlign(.left, .middle)
            drawText(labels[k], x + 24, y)
        }
        noFill()
        noStroke()
        fill(theme.muted)
        textSize(13)
        textAlign(.left, .top)
        drawText("0 s", chart.x, chart.y + chart.height + 8)
        textAlign(.right, .top)
        drawText("12 s", chart.x + chart.width, chart.y + chart.height + 8)
        textAlign(.right, .middle)
        drawText("r = 1", chart.x - 8, chart.y)
        drawText("r = 0", chart.x - 8, chart.y + chart.height)
        textAlign(.center, .top)
        fill(theme.ink)
        textSize(15)
        drawText("the coherence over time, three pulls", chart.x + chart.width / 2, 36)

        diagramCaption("below the critical coupling nothing locks; above it, everything", at: 348, theme: theme)
    }
}
