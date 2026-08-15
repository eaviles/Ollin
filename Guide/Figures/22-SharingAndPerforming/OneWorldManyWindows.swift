// figure: frame=1
//
// Guide diagram (Chapter 22): three windows of one sketch, open on one desk.
// The world is drawn in desk coordinates, so each window shows the part of it
// that falls inside its own rectangle, and the rings carry on across the gaps
// between them. Faint outside the windows is the part nobody is looking at.
import Ollin

final class OneWorldManyWindows: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let rule = Color(hex: 0x2B2B2B, alpha: 0.18)
    let dark = Color(hex: 0x141618)
    let accent = Color(hex: 0xE4572E)

    /// The desk, in the figure's own coordinates.
    let desk = Rectangle(x: 56, y: 92, width: 768, height: 380)

    /// Three windows somebody dragged where they wanted them.
    var windows: [Rectangle] {
        [Rectangle(x: 92, y: 128, width: 250, height: 168),
         Rectangle(x: 392, y: 128, width: 300, height: 190),
         Rectangle(x: 120, y: 330, width: 236, height: 118)]
    }

    override func draw() {
        background(paper)

        textSize(20)
        textAlign(.left, .top)
        fill(ink)
        drawText("one world, three windows", 56, 40)

        // The desk itself: the whole area the windows are dragged around in.
        noFill()
        stroke(rule)
        strokeWeight(1)
        drawRect(corner: Vector2(desk.x, desk.y), width: desk.width, height: desk.height)
        textSize(14)
        fill(soft)
        textAlign(.right, .top)
        drawText("the desk", desk.x + desk.width, desk.y + desk.height + 10)

        // The world, drawn once faintly across the whole desk. Nobody sees
        // this part: it is here so the reader can tell that the windows are
        // holes cut in one picture rather than three pictures.
        world(alpha: 0.16)

        // Each window: a dark pane with the same world drawn inside it, at
        // full strength, clipped to the pane.
        textAlign(.center, .center)
        for (index, window) in windows.enumerated() {
            noStroke()
            fill(dark)
            drawRect(corner: Vector2(window.x, window.y - 18),
                     width: window.width, height: window.height + 18)
            withClip(window) {
                world(alpha: 1)
            }
            // Three dots for a title bar, so a pane reads as a window.
            fill(Color(white: 1, alpha: 0.35))
            for dot in 0..<3 {
                drawCircle(window.x + 14 + Double(dot) * 13, window.y - 9, 3.5)
            }
            fill(Color(white: 1, alpha: 0.5))
            textSize(12)
            drawText("window \(index + 1)", window.center.x, window.y - 9)
        }

        // What each window knows about itself.
        let second = windows[1]
        stroke(accent)
        strokeWeight(1.5)
        drawLine(second.x, second.y + second.height,
                 second.x, second.y + second.height + 26)
        drawLine(second.x, second.y + second.height + 26,
                 second.x + second.width, second.y + second.height + 26)
        drawLine(second.x + second.width, second.y + second.height,
                 second.x + second.width, second.y + second.height + 26)
        noStroke()
        fill(accent)
        textSize(13)
        textAlign(.center, .top)
        drawText("canvasOnScreen: where this one sits on the desk",
                 second.center.x, second.y + second.height + 32)

        fill(soft)
        textSize(14)
        textAlign(.left, .top)
        drawText("Each window draws in desk coordinates, so the rings carry on across the gaps.",
                 56, desk.y + desk.height + 62)
        drawText("Nothing is sent between them: the world is a function of the time of day.",
                 56, desk.y + desk.height + 84)
    }

    /// The world: rings around the middle of the desk, and dots scattered over
    /// it. Drawn in desk coordinates, which is the whole point.
    private func world(alpha: Double) {
        let middle = desk.center
        noFill()
        stroke(Color(hex: 0x6B9EC7, alpha: alpha * 0.85))
        strokeWeight(1.5)
        for ring in 1...6 {
            drawCircle(center: middle, radius: Double(ring) * 34)
        }

        let colors = [Color(hex: 0xE4572E, alpha: alpha),
                      Color(hex: 0x2E6FBF, alpha: alpha),
                      Color(hex: 0xE8B84B, alpha: alpha),
                      Color(hex: 0xFFFFFF, alpha: alpha)]
        for dot in 0..<70 {
            let place = Vector2(desk.x + steady(dot, 1) * desk.width,
                                desk.y + steady(dot, 2) * desk.height)
            let size = 4 + steady(dot, 3) * 13
            let ink = colors[dot % colors.count]
            if steady(dot, 4) < 0.35 {
                noFill()
                stroke(ink)
                strokeWeight(2)
                drawCircle(center: place, radius: size)
            } else {
                noStroke()
                fill(ink)
                drawCircle(center: place, radius: size)
            }
        }
    }

    /// A steady number between 0 and 1, read from the dot's own number so the
    /// figure is the same every time it is rendered.
    private func steady(_ index: Int, _ salt: Int) -> Double {
        var bits = UInt64(truncatingIfNeeded: index &* 374_761_393 &+ salt &* 668_265_263)
        bits ^= bits >> 31
        bits = bits &* 0x9E37_79B9_7F4A_7C15
        bits ^= bits >> 29
        return Double(bits % 100_000) / 100_000
    }
}
