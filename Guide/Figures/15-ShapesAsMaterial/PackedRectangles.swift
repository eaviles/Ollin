// figure: frame=0 themed
//
// Guide diagram (Chapter 15): one set of forty rectangles of mixed
// proportions packed into the same square bin twice. Left, every rectangle
// stays upright, and the ones that did not fit wait in a row underneath.
// Right, a rectangle may turn a quarter turn when that fits it better; the
// turned ones carry a diagonal. The sizes come from a fixed seed.
import Ollin
import OllinDiagram

final class PackedRectangles: Sketch {
    override var canvasSize: CanvasSize { .size(1080, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    /// Forty sizes, mostly long and thin, from a fixed seed.
    var sizes: [Vector2] {
        var rng = SplitMix64(seed: 5)
        return (0 ..< 40).map { _ in
            let long = Double.random(in: 50 ... 150, using: &rng).rounded()
            let short = Double.random(in: 20 ... 60, using: &rng).rounded()
            return Bool.random(using: &rng) ? Vector2(long, short) : Vector2(short, long)
        }
    }

    override func draw() {
        background(paper)
        let sizes = sizes
        panel(at: Vector2(40, 70), sizes: sizes, rotation: false, title: "upright",
              note: "packRectangles(sizes, in: bin, padding: 4)")
        panel(at: Vector2(580, 70), sizes: sizes, rotation: true, title: "turned when it fits better",
              note: "… allowsRotation: true)")
    }

    func panel(at origin: Vector2, sizes: [Vector2], rotation: Bool, title: String, note: String) {
        withState {
            translate(origin)
            let bin = Rectangle(x: 0, y: 0, width: 460, height: 400)
            let packing = packRectangles(sizes, in: bin, padding: 4, allowsRotation: rotation)
            noStroke()
            fill(ink)
            textSize(19)
            textAlign(.left, .middle)
            drawText(title, 0, -34)

            for place in packing.placed {
                fill(ink.withAlpha(0.18 + 0.5 * Double(place.index % 5) / 4))
                drawRect(place.rectangle)
            }
            stroke(paper)
            strokeWeight(2)
            for place in packing.placed where place.isRotated {
                drawLine(place.rectangle.topLeft, place.rectangle.bottomRight)
            }
            noFill()
            stroke(accent)
            strokeWeight(2)
            drawRect(bin.inset(by: .all(-4)))

            // What did not fit, at half size in a row underneath.
            noStroke()
            fill(ink.withAlpha(0.7))
            textSize(15)
            textAlign(.left, .top)
            let count = packing.unplaced.count
            drawText(count == 0 ? "\(Int((packing.occupancy * 100).rounded()))% of the bin covered, every one placed"
                     : "\(Int((packing.occupancy * 100).rounded()))% covered; \(count) did not fit", 0, 414)
            var x = 0.0
            for index in packing.unplaced {
                let s = sizes[index] * 0.5
                noFill()
                stroke(ink.withAlpha(0.6))
                strokeWeight(1.5)
                drawRect(Rectangle(x: x, y: 446, width: s.x, height: s.y))
                x += s.x + 8
            }
            noStroke()
            fill(ink.withAlpha(0.7))
            textAlign(.left, .top)
            drawText(note, 0, 520)
        }
    }
}
