import Ollin

/// A pen you drive from code. A `Turtle` stands on the canvas facing some way;
/// it walks forward, turns, lifts and lowers its pen, and remembers where it
/// stood, and the path comes back as contours. On the left a tree grows by
/// the oldest turtle program there is: walk the trunk, remember the spot,
/// turn left and grow a smaller tree, come back, turn right and grow another
/// (`pushState`/`popState`). The wind leans the whole tree by nudging every
/// turn. On the right a polyspiral walks ever longer steps with the same turn
/// after each, and the turn slides over the loop so the figure opens and
/// closes.
///
/// ```sh
/// swift run Example-Patterns-TurtleWalk --export-loop /tmp/turtle.gif
/// ```
///
/// Every run is an ordinary open contour, so the whole picture plots as lines.
@main
final class TurtleWalk: Sketch {
    @Param(3 ... 10, icon: "tree") var depth = 8
    @Param(10 ... 60, icon: "angle") var spread = 24.0
    @Param(0.55 ... 0.8, icon: "arrow.down.right.and.arrow.up.left") var shrink = 0.7
    @Param(40 ... 140, icon: "tornado") var steps = 90

    let period = 12.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0xF4EFE6))
        let t = time / period * 2 * .pi
        let wind = 6 * sin(t)

        // The tree: one turtle, one recursive program.
        var tree = Turtle(at: Vector2(width * 0.28, height * 0.92))
        grow(&tree, length: height * 0.2, depth: depth, wind: wind)
        strokeCap(.round)
        noFill()
        // A limb's length says how far down the tree it is, since every branch
        // is `shrink` of the one it grows from, so the trunk is thick and dark
        // and the twigs thin and pale.
        let runs = tree.contours
        let longest = runs.map(\.length).max() ?? 1
        for run in runs {
            let share = run.length / longest
            strokeWeight(1 + 6 * share * share)
            stroke(Color(hue: 0.36 - 0.06 * share, saturation: 0.3 + 0.2 * share, brightness: 0.7 - 0.35 * share))
            drawPolyline(run.points, closed: false)
        }

        // The polyspiral: step 1, 2, 3 … and the same turn after each.
        let turn = 90 + 30 * sin(t * 0.5)
        var spiral = Turtle(at: Vector2(width * 0.72, height * 0.5), heading: -90)
        for i in 1 ... steps {
            spiral.forward(Double(i) * height * 0.0042)
            spiral.right(turn)
        }
        let figure = spiral.contours[0]
        let box = Rectangle(x: width * 0.52, y: height * 0.1, width: width * 0.42, height: height * 0.8)
        strokeWeight(2)
        stroke(Color(hex: 0xB8442F))
        drawPolyline(fitted(figure.points, in: box), closed: false)
    }

    /// Walk a limb, then grow the two branches from its tip and come back.
    func grow(_ turtle: inout Turtle, length: Double, depth: Int, wind: Double) {
        guard depth > 0 else { return }
        turtle.forward(length)
        turtle.pushState()
        turtle.left(spread - wind)
        grow(&turtle, length: length * shrink, depth: depth - 1, wind: wind)
        turtle.popState()
        turtle.pushState()
        turtle.right(spread + wind)
        grow(&turtle, length: length * shrink, depth: depth - 1, wind: wind)
        turtle.popState()
    }
}
