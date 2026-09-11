// figure: frame=0 themed
//
// Docs catalog figure (Generators/Fracture.md): the same disc broken two ways
// by the same seed. Spread the seeds evenly and the pieces come out of a
// size; crowd them at a point and the break reads as a strike there, small
// chips at the blow and long wedges away from it. The pieces are drawn pulled
// a little off their own centers so the cut lines read; in the sketch they sit
// exactly where the shape was.
import Ollin
import OllinDiagram

final class FractureCut: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The shape both panels break: one disc, 48 points around.
    var disc: Shape {
        Shape((0 ..< 48).map { i in
            let a = Double(i) / 48 * .tau
            return Vector2(cos(a), sin(a)) * 132
        })
    }

    override func draw() {
        background(theme.paper)
        seed(3)

        panel(at: Vector2(228, 190), pieces: disc.fractured(into: 16, seed: 3),
              label: "fractured(into: 16, seed: 3)")

        let blow = Vector2(-84, -70)
        panel(at: Vector2(652, 190), pieces: disc.fractured(into: 16, around: blow, seed: 3),
              label: "fractured(into: 16, around: blow, seed: 3)", blow: blow)
    }

    /// One panel: the pieces eased off their own centers, the blow marked.
    func panel(at center: Vector2, pieces: [Shape], label: String, blow: Vector2? = nil) {
        withState {
            translate(center)
            for piece in pieces {
                withState {
                    translate(piece.centroid.normalized * 6)
                    fill(theme.ink(0.08))
                    stroke(theme.ink(0.55))
                    strokeWeight(1.5)
                    drawShape(piece)
                }
            }
            if let blow {
                noStroke()
                fill(theme.accent)
                drawCircle(center: blow, radius: 7)
            }
        }

        noStroke()
        fill(theme.muted)
        textSize(17)
        textAlign(.center, .top)
        drawText(label, center.x, center.y + 162)
    }
}
