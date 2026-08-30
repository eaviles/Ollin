import Ollin

/// A ring of beads where any three in a row say where you are.
///
/// The ring carries a de Bruijn sequence: four colors, sixty-four beads, and every
/// possible run of three colors appearing exactly once around it. Nothing is
/// repeated and nothing is missing, which is as short as such a ring can be, since
/// there are sixty-four runs of three to fit and each takes one place.
///
/// That is what makes it useful rather than merely pretty. The reader below sees
/// three beads and nothing else, and those three are enough to say where on the
/// ring it is, because no other three look the same. A rotary encoder finds its
/// angle this way, and a camera finds its place on a printed ruler the same way.
///
/// The reader walks the ring over the loop. Hold the mouse and it follows the
/// pointer instead, so any three beads can be asked.
@main
final class DeBruijn_Example: Sketch {
    override var loopDuration: Double? { 16 }

    private let code = DeBruijnCode(symbols: 4, window: 3)
    private let inks = [Color(hex: 0xE8514B), Color(hex: 0xFFC24B),
                        Color(hex: 0x4BC0E8), Color(hex: 0x9B7BE8)]

    override func draw() {
        background(Color(hex: 0x0B0E14))
        let beads = code.sequence.count
        let middle = bounds.center
        let radius = shortSide * 0.34

        // Where the reader sits: walking over the loop, or under the pointer.
        let angle = mouseIsPressed
            ? (mouse - middle).angle
            : loopProgress(over: 16) * .tau - .pi / 2
        let at = ((Int(((angle + .pi / 2) / .tau * Double(beads)).rounded(.down)) % beads) + beads) % beads

        // The beads themselves, as arcs around the ring.
        let step = Double.tau / Double(beads)
        noFill()
        strokeCap(.butt)
        for (index, symbol) in code.sequence.enumerated() {
            let start = Double(index) * step - .pi / 2
            let inWindow = (0 ..< code.window).contains { (at + $0) % beads == index }
            stroke(inks[symbol].withAlpha(inWindow ? 1 : 0.4))
            strokeWeight(inWindow ? 44 : 26)
            drawArc(center: middle, radiusX: radius, radiusY: radius,
                    start: start + step * 0.08, stop: start + step * 0.92)
        }

        // What the reader sees, and where that says it is.
        let seen = (0 ..< code.window).map { code.sequence[(at + $0) % beads] }
        let found = code.position(of: seen)

        noStroke()
        textAlign(.center, .middle)
        for (offset, symbol) in seen.enumerated() {
            fill(inks[symbol])
            drawCircle(middle.x + Double(offset - 1) * 58, middle.y - 26, 22)
        }
        fill(Color(white: 0.92))
        textSize(30)
        drawText(found.map { "bead \($0)" } ?? "nowhere", at: middle + Vector2(0, 40))
        textSize(17)
        fill(Color(white: 0.6))
        drawText("of \(beads)", at: middle + Vector2(0, 76))

        // The line from the reader out to the beads it is reading.
        stroke(Color(white: 0.5, alpha: 0.5))
        strokeWeight(1)
        let toward = Double(at) * step - .pi / 2 + step * Double(code.window) / 2
        drawLine(middle + Vector2(angle: toward, length: 118),
                 middle + Vector2(angle: toward, length: radius - 30))

        drawCaption("four colors, \(beads) beads, every run of \(code.window) exactly once; "
            + (mouseIsPressed ? "reading where the pointer is" : "hold the mouse to aim the reader"))
    }
}
