import Ollin

/// A piece lined up with the thing it is thrown onto.
///
/// A projector is almost never square to its wall. It hangs off a beam or sits
/// on a shelf to one side, and the picture lands as a trapezoid a few degrees
/// out of true. So this window fits its picture in the present pass rather than
/// in the layout: press **Command-K**, drag the four corners onto whatever the
/// work is meant to sit inside, and press it again. The numbers are kept under
/// the display, so the next launch opens already square, and any other piece you
/// show on that projector opens square too.
///
/// The frame and the corner ticks below are there for that minute of dragging.
/// The rest is the work.
///
/// One machine covers a wall on its own here. Two machines cover a longer one by
/// each carrying a part of the canvas and sharing a band in the middle:
///
/// ```swift
/// // The machine on the left.
/// Installation(projection: .init(visibleRegion: Rectangle(x: 0, y: 0, width: 0.6, height: 1),
///                                blend: Insets(right: 0.2)))
/// // The machine on the right.
/// Installation(projection: .init(visibleRegion: Rectangle(x: 0.4, y: 0, width: 0.6, height: 1),
///                                blend: Insets(left: 0.2)))
/// ```
///
/// Both are told the same tenth of the same canvas, so their two fades are the
/// same function of the same wall and add up to one coat with no bright bar down
/// the join. See `Docs/Output/Installation.md`.
///
/// To work on it in an ordinary window, run it with `--no-installation`.
@main
final class Fitted: Sketch {

    override var installation: Installation { .on }

    override var loopDuration: Double? { 60 }

    private let ink = Ramp([Color(red: 0.10, green: 0.13, blue: 0.22),
                            Color(red: 0.24, green: 0.51, blue: 0.62),
                            Color(red: 0.93, green: 0.79, blue: 0.44)])

    override func draw() {
        background(Color(white: 0.04))
        drawTheWork()
        drawTheRegistration()
    }

    /// The piece itself: a slow tide of bars, built from where each bar stands
    /// and how far along the lap the run is, so it repeats exactly.
    private func drawTheWork() {
        noStroke()
        let lap = loopProgress(over: 60) * .tau
        let columns = 26
        let step = width / Double(columns)
        for column in 0..<columns {
            let x = (Double(column) + 0.5) * step
            let phase = Double(column) / Double(columns) * .tau * 1.5
            let tide = unipolar(sin(lap + phase))
            let bar = height * (0.12 + 0.62 * tide)
            fill(ink.color(at: tide))
            drawRect(center: Vector2(x, height / 2), width: step * 0.55, height: bar)
        }
    }

    /// What you line the corners up with: the edge of the canvas, a tick at each
    /// corner, and a cross in the middle. Everything a hand needs to tell
    /// whether the picture is sitting where it should.
    private func drawTheRegistration() {
        noFill()
        stroke(Color(white: 0.85, alpha: 0.7))
        strokeWeight(2)
        drawRect(corner: Vector2(1, 1), width: width - 2, height: height - 2)

        let tick = shortSide * 0.06
        strokeWeight(3)
        stroke(Color(white: 1, alpha: 0.9))
        for corner in [Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)] {
            let toward = Vector2(corner.x == 0 ? 1 : -1, corner.y == 0 ? 1 : -1)
            drawLine(corner, Vector2(corner.x + tick * toward.x, corner.y))
            drawLine(corner, Vector2(corner.x, corner.y + tick * toward.y))
        }

        strokeWeight(1.5)
        stroke(Color(white: 1, alpha: 0.5))
        drawLine(Vector2(center.x - tick, center.y), Vector2(center.x + tick, center.y))
        drawLine(Vector2(center.x, center.y - tick), Vector2(center.x, center.y + tick))
    }
}
