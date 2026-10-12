import Ollin

/// Shapes as values that know where they cross. A line, two circles, an arc,
/// an ellipse, and a rectangle drift across the canvas, each held as the
/// typed value behind its draw call (`LineSegment`, `Circle`, `Arc`,
/// `Ellipse`, `Rectangle`). Every frame each pair is asked where it meets
/// the other (`crossings(with:)`), and a dot marks every answer: a segment
/// against a circle or an ellipse is a quadratic, two circles are the
/// two-circle construction, and the ellipse against anything round is found
/// on the outlines and polished onto the true curves. The shapes are drawn
/// through the same values (`drawLine(_:)`, `drawArc(_:)`, `drawEllipse(_:)`).
///
/// A probe follows the mouse and drops a line to the nearest place on every
/// shape (`nearestPoint(to:)`), with the ellipse's exact perimeter written
/// beside it.
///
/// ```sh
/// swift run Example-Shapes-Crossings --export-loop /tmp/crossings.gif
/// ```
@main
final class Crossings: Sketch {
    @Param(2 ... 14, icon: "circle.fill") var dotSize = 7.0
    @Param(icon: "scope") var showsNearest = true

    let period = 14.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x14161C))
        let t = time / period * 2 * .pi
        let w = width, h = height

        // The cast, each placed by a slow sine so the picture loops.
        let road = LineSegment(Vector2(0.06 * w, h * (0.52 + 0.22 * sin(t))),
                               Vector2(0.94 * w, h * (0.48 - 0.22 * sin(t + 0.7))))
        let left = Circle(center: Vector2(w * (0.32 + 0.08 * cos(t)), h * (0.42 + 0.06 * sin(2 * t))),
                          radius: 0.16 * w)
        let right = Circle(center: Vector2(w * (0.64 + 0.07 * sin(t)), h * (0.58 + 0.05 * cos(t))),
                           radius: 0.13 * w)
        let dish = Ellipse(center: Vector2(w * 0.5, h * (0.5 + 0.14 * sin(t * 1.5))),
                           radiusX: 0.3 * w, radiusY: 0.11 * w, rotation: t * 0.5)
        let bow = Arc(center: Vector2(w * 0.5, h * 0.55), radius: 0.36 * w,
                      start: .pi * 1.05 + 0.3 * sin(t), stop: .pi * 1.95 + 0.3 * sin(t))
        let frame = Rectangle(center: Vector2(w * (0.5 + 0.05 * cos(t * 0.5)), h * 0.5),
                              width: 0.56 * w, height: 0.5 * h)
        let cast: [any PlaneCurve] = [road, left, right, dish, bow, frame]

        noFill()
        strokeWeight(2.5)
        stroke(Color(hex: 0x7F8CA8))
        drawLine(road)
        stroke(Color(hex: 0xE5B15C))
        drawCircle(left)
        drawCircle(right)
        stroke(Color(hex: 0x9FD6E8))
        drawEllipse(dish)
        stroke(Color(hex: 0xF4EAD6))
        drawArc(bow)
        stroke(Color(hex: 0x6BD69B))
        drawRect(frame)

        // Where the probe lands on each curve.
        if showsNearest {
            let probe = mouseIsPressed ? Vector2(mouseX, mouseY)
                : Vector2(w * (0.5 + 0.38 * cos(t * 0.7)), h * (0.5 + 0.38 * sin(t * 0.9)))
            strokeWeight(1)
            stroke(Color(white: 1, alpha: 0.35))
            for place in [road.nearestPoint(to: probe), left.nearestPoint(to: probe),
                          right.nearestPoint(to: probe), dish.nearestPoint(to: probe),
                          bow.nearestPoint(to: probe), frame.contour.nearestPoint(to: probe)] {
                drawLine(probe, place)
            }
            noStroke()
            fill(.white)
            drawCircle(center: probe, radius: 5)
        }

        // Every pair asked once; a dot per answer.
        noStroke()
        fill(Color(hex: 0xFF6B6B))
        var count = 0
        for i in cast.indices {
            for j in cast.indices where j > i {
                for hit in cast[i].crossings(with: cast[j]) {
                    drawCircle(center: hit, radius: dotSize)
                    count += 1
                }
            }
        }

        fill(Color(white: 0.8))
        textSize(22)
        textAlign(.left, .bottom)
        drawText("\(count) crossings, ellipse perimeter \(Int(dish.perimeter.rounded()))",
                 0.04 * w, 0.96 * h)
    }
}
