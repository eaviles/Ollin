// figure: frame=0
//
// Guide figure (Chapter 21): what a `reach` is for, and what it buys. Three
// panels of the same courtyard, each rendered on its own through
// `OllinApp.image(of:)` and drawn here as read-back pixels, because each panel
// needs its own light set and one frame carries one. Left: twelve lamps with no
// reach, every one of them carrying the whole courtyard, which is one flat wash
// with no night in it. Middle: the same twelve with a reach, each owning a pool.
// Right: sixty-four of them, which the plain path could not have held at all.
import Ollin

final class LampsAtNight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    /// One courtyard: `lamps` point lights over a floor of blocks, with or without
    /// a bound on how far each one carries.
    final class Courtyard: Sketch {
        var lamps = 12
        var reach: Double?

        override var canvasSize: CanvasSize { .square(280) }

        override func draw() {
            seed(4)
            background(Color(hex: 0x05060A))
            ambientLight(Color(white: 0.02))
            camera(.perspective(eye: Vector3(0, 30, 40), target: Vector3(0, 1, 0),
                                fieldOfView: .pi / 4.4))
            // The lamps sit on a ring-ish scatter over the whole floor, so at both
            // counts they are spread rather than piled.
            for i in 0..<lamps {
                let turn = Double(i) * 2.399963   // the golden angle, so any count spreads
                let radius = 4.0 + 22.0 * (Double(i) / Double(max(lamps - 1, 1))).squareRoot()
                pointLight(Color(hue: Double(i) * 0.137 - (Double(i) * 0.137).rounded(.down),
                                 saturation: 0.8, brightness: 1),
                           at: Vector3(cos(turn) * radius, 3.0, sin(turn) * radius),
                           intensity: 1.7, reach: reach)
            }
            fill(Color(white: 0.52))
            withState {
                translate(0, -0.05, 0)
                drawBox(width: 120, height: 0.1, depth: 120)
            }
            fill(Color(white: 0.64))
            for row in stride(from: -24.0, through: 24.0, by: 6.0) {
                for column in stride(from: -24.0, through: 24.0, by: 6.0) {
                    withState {
                        translate(column, 1.1, row)
                        drawBox(width: 3.0, height: 2.2, depth: 3.0)
                    }
                }
            }
        }
    }

    private func panel(lamps: Int, reach: Double?) -> Image? {
        let scene = Courtyard()
        scene.lamps = lamps
        scene.reach = reach
        guard let rendered = OllinApp.image(of: scene) else { return nil }
        return Image(cgImage: rendered)
    }

    override func draw() {
        background(Color(hex: 0x111318))

        let captions = ["twelve lamps, no reach", "twelve lamps, reach 14", "sixty-four, reach 10"]
        let panels = [panel(lamps: 12, reach: nil),
                      panel(lamps: 12, reach: 14),
                      panel(lamps: 64, reach: 10)]

        let side = 260.0, gap = 20.0
        let left = (width - (side * 3 + gap * 2)) / 2
        for (index, picture) in panels.enumerated() {
            let x = left + Double(index) * (side + gap)
            if let picture { drawImage(picture, x, 40, side, side) }
            fill(Color(white: 0.82))
            textSize(15)
            textAlign(.center, .top)
            drawText(captions[index], x + side / 2, 40 + side + 14)
        }

        fill(Color(white: 0.55))
        textSize(13)
        textAlign(.center, .top)
        drawText("a lamp that carries forever leaves no night between the lamps",
                 width / 2, 40 + side + 44)
    }
}
