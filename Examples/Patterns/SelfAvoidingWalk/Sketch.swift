import Ollin

/// One unbroken line that never crosses itself.
///
/// `selfAvoidingWalk` threads a random path through a lattice, refusing every
/// cell it has already visited. A naive version boxes itself in almost
/// immediately; this one backtracks out of dead ends (the abandoned cells
/// stay blocked), so the line winds long and dense, filling the frame the way
/// a maze fills a page. The result is a single stroke you could draw without
/// lifting the pen, which is exactly what makes it a favorite for plotters.
///
/// Color runs along the path's length, so you can read the story of the walk:
/// where it started, where it squeezed through, where it finally ran out of
/// room. A bright runner retraces it out and back over the loop.
@main
final class SelfAvoidingWalk: Sketch {
    private let ramp = Ramp([Color(hex: 0x2C7DA0), Color(hex: 0x8FBFA0),
                             Color(hex: 0xE9C46A), Color(hex: 0xD1495B)])
    private var path: [Vector2] = []

    override var loopDuration: Double? { 20 }

    override func setup() {
        seed(12)
        path = selfAvoidingWalk(in: canvasRectangle.inset(by: 70), cellSize: 30)
    }

    override func draw() {
        background(Color(hex: 0x14161D))
        strokeCap(.round)

        // The whole walk, hue by age: the round caps at the shared corners
        // read as smooth joints.
        strokeWeight(11)
        for i in 1 ..< path.count {
            stroke(ramp.color(at: Double(i) / Double(path.count - 1)))
            drawLine(path[i - 1], path[i])
        }

        // The runner: a bright window sliding along the path, out and back.
        let head = pingPong(over: 20) * Double(path.count - 1)
        let headIndex = max(Int(head), 1)
        let window = 26
        for k in max(headIndex - window, 1) ... headIndex {
            let age = Double(headIndex - k) / Double(window)
            stroke(Color.white.withAlpha((1 - age) * 0.85))
            strokeWeight(5)
            drawLine(path[k - 1], path[k])
        }

        drawCaption("\(path.count) cells, one stroke, no crossings")
    }
}
