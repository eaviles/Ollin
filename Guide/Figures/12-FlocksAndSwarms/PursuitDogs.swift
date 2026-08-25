// figure: frame=0 themed
//
// Guide diagram (Chapter 12): pursuit. Left, four dogs on a square, each
// running at the next: the square stays a square as it shrinks and turns, and
// every path is the same spiral. Right, the other classic case, a quarry that
// runs straight and a faster pursuer that curves in behind it.
import Ollin
import OllinDiagram

final class PursuitDogs: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)
        textSize(17)

        dogsPanel(Rectangle(x: 50, y: 60, width: 370, height: 400))
        quarryPanel(Rectangle(x: 470, y: 60, width: 370, height: 400))
    }

    func dogsPanel(_ r: Rectangle) {
        frame(r, title: "four dogs, each running at the next")
        let middle = Vector2(r.center.x, r.center.y - 10)
        let radius = 118.0
        let chase = Pursuit.ring(sides: 4, center: middle, radius: radius,
                                 turn: .pi / 4, stepSize: radius / 500)
        chase.recordEvery = 40
        chase.run()

        // The square they start on, and the chase lines kept along the way.
        let corners = chase.runners.map { $0.trail[0] }
        noFill()
        stroke(faint)
        strokeWeight(2)
        drawPolygon(corners)
        stroke(soft)
        strokeWeight(1.5)
        for line in chase.web { drawPolyline(line.points) }

        // Every path is the same curve. One is picked out to be followed.
        strokeWeight(2)
        for (index, trail) in chase.trails.enumerated() {
            stroke(index == 0 ? accent : ink)
            drawPolyline(trail.points)
        }
        noStroke()
        for (index, corner) in corners.enumerated() {
            fill(index == 0 ? accent : ink)
            drawCircle(center: corner, radius: 6)
        }

        // Which way the chase runs, on the edge between the first two.
        arrow(from: corners[0].lerp(to: corners[1], 0.28),
              to: corners[0].lerp(to: corners[1], 0.72), color: accent, weight: 2.5)

        label("each dog runs exactly", Vector2(r.center.x, r.y + 330))
        label("one side of the square", Vector2(r.center.x, r.y + 352))
    }

    func quarryPanel(_ r: Rectangle) {
        frame(r, title: "a quarry that runs straight")
        let start = Vector2(r.x + 95, r.y + 330)
        let chase = Pursuit(runners: [.holding(Vector2(0, -1), from: start, speed: 0.55),
                                      .chasing(0, from: start + Vector2(200, 0))],
                            stepSize: 1.2)
        chase.run()

        noFill()
        strokeWeight(2)
        stroke(faint)
        drawPolyline(chase.trails[0].points)
        stroke(accent)
        drawPolyline(chase.trails[1].points)

        noStroke()
        fill(faint)
        drawCircle(center: start, radius: 6)
        fill(accent)
        drawCircle(center: start + Vector2(200, 0), radius: 6)
        fill(ink)
        drawCircle(center: chase.runners[1].position, radius: 5)

        label("it aims at where the quarry is,", Vector2(r.center.x, r.y + 36))
        label("never at where it is going", Vector2(r.center.x, r.y + 58))
        label("caught here", chase.runners[1].position + Vector2(56, -16))
        label("the quarry", start + Vector2(0, 28))
        label("the pursuer", start + Vector2(200, 28), color: accent)
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

    func arrow(from a: Vector2, to b: Vector2, color: Color, weight: Double = 3) {
        let dir = (b - a).normalized
        stroke(color)
        strokeWeight(weight)
        drawLine(a, b - dir * 10)
        noStroke()
        fill(color)
        drawPolygon([b, b - dir * 14 + dir.perpendicular * 5,
                        b - dir * 14 - dir.perpendicular * 5])
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
