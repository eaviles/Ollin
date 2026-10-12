// figure: frame=0 themed
//
// Guide diagram (Chapter 15): shapes as values that know where they cross.
// Left, a line through a circle and an ellipse, with a dot on every meeting
// and a probe dropped to the nearest place on the ellipse. Middle, two
// circles that meet twice, and the same two as arcs that keep only the one
// meeting on their sweeps. Right, six curves of every kind with a dot on
// every crossing of every pair. Nothing here uses randomness.
import Ollin
import OllinDiagram

final class CurvesThatCross: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.3) }
    let accent = Color(hex: 0xE07A5F)
    let cool = Color(hex: 0x3D7EA6)

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 48, y: 60, width: 248, height: 248),
                      Rectangle(x: 316, y: 60, width: 248, height: 248),
                      Rectangle(x: 584, y: 60, width: 248, height: 248)]

        // Left: a line through a circle and an ellipse.
        do {
            let p = panels[0]
            let road = LineSegment(p.point(u: 0.05, v: 0.78), p.point(u: 0.95, v: 0.18))
            let pond = Circle(center: p.point(u: 0.34, v: 0.46), radius: p.width * 0.2)
            let dish = Ellipse(center: p.point(u: 0.66, v: 0.52), radiusX: p.width * 0.27,
                               radiusY: p.width * 0.12, rotation: -0.5)
            noFill()
            strokeWeight(2)
            stroke(soft)
            drawLine(road)
            stroke(ink)
            drawCircle(pond)
            stroke(cool)
            drawEllipse(dish)
            let probe = p.point(u: 0.84, v: 0.9)
            stroke(soft)
            strokeWeight(1.2)
            drawLine(probe, dish.nearestPoint(to: probe))
            noStroke()
            fill(ink)
            drawCircle(center: probe, radius: 4)
            fill(accent)
            for hit in road.crossings(with: pond) + road.crossings(with: dish) {
                drawCircle(center: hit, radius: 5.5)
            }
        }

        // Middle: two circles, then the same two as arcs.
        do {
            let p = panels[1]
            let a = Circle(center: p.point(u: 0.38, v: 0.3), radius: p.width * 0.2)
            let b = Circle(center: p.point(u: 0.62, v: 0.3), radius: p.width * 0.2)
            noFill()
            strokeWeight(2)
            stroke(ink)
            drawCircle(a)
            drawCircle(b)
            noStroke()
            fill(accent)
            for hit in a.crossings(with: b) { drawCircle(center: hit, radius: 5.5) }
            // The lower halves only, so one of the two meetings is off both sweeps.
            let arcA = Arc(center: p.point(u: 0.38, v: 0.72), radius: p.width * 0.2, start: 0, stop: .pi)
            let arcB = Arc(center: p.point(u: 0.62, v: 0.72), radius: p.width * 0.2, start: 0, stop: .pi)
            noFill()
            stroke(ink)
            strokeWeight(2)
            drawArc(arcA)
            drawArc(arcB)
            stroke(soft)
            strokeWeight(1)
            drawArc(Arc(center: arcA.center, radius: arcA.radius, start: .pi, stop: 2 * .pi))
            drawArc(Arc(center: arcB.center, radius: arcB.radius, start: .pi, stop: 2 * .pi))
            noStroke()
            fill(accent)
            for hit in arcA.crossings(with: arcB) { drawCircle(center: hit, radius: 5.5) }
        }

        // Right: every pair of a mixed list.
        do {
            let p = panels[2]
            let cast: [any PlaneCurve] = [
                LineSegment(p.point(u: 0.04, v: 0.62), p.point(u: 0.96, v: 0.3)),
                Circle(center: p.point(u: 0.34, v: 0.42), radius: p.width * 0.19),
                Circle(center: p.point(u: 0.64, v: 0.58), radius: p.width * 0.15),
                Ellipse(center: p.point(u: 0.5, v: 0.5), radiusX: p.width * 0.36, radiusY: p.width * 0.13, rotation: 0.4),
                Arc(center: p.point(u: 0.5, v: 0.6), radius: p.width * 0.4, start: .pi * 1.1, stop: .pi * 1.9),
                Rectangle(center: p.point(u: 0.5, v: 0.5), width: p.width * 0.64, height: p.height * 0.5),
            ]
            noFill()
            strokeWeight(1.6)
            for (i, curve) in cast.enumerated() {
                stroke(i % 2 == 0 ? ink : cool)
                let outline = curve.contour
                drawPolyline(outline.points, closed: outline.isClosed)
            }
            noStroke()
            fill(accent)
            for i in cast.indices {
                for j in cast.indices where j > i {
                    for hit in cast[i].crossings(with: cast[j]) { drawCircle(center: hit, radius: 4.5) }
                }
            }
        }

        diagramFrame(panels[0], title: "a line, a circle, an ellipse", theme: theme)
        diagramFrame(panels[1], title: "arcs keep their sweep", theme: theme)
        diagramFrame(panels[2], title: "every pair of a list", theme: theme)
        diagramCaption("each shape is a value, and any two can be asked where they cross", at: 340, theme: theme)
        drawText("LineSegment, Arc, Circle, Ellipse, Rectangle, and Contour, through crossings(with:)",
                 width / 2, 374, size: 17, color: theme.muted, align: .center, .top)
    }
}
