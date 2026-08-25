import Foundation
import Ollin

/// The `extend(...)` seam: a reusable overlay that draws *over* the sketch every
/// frame, without `draw()` knowing about it.
///
/// `Guides` is a `SketchExtension`. Its `afterDraw` runs right after `draw()`,
/// before the frame renders, so it composites on top — here, an inset border and
/// a center crosshair, the registration marks you'd want while composing. The
/// sketch registers it once in `setup()` and otherwise stays focused on its own
/// drawing. Swap in your own extension the same way; observers that read timing
/// rather than draw use `afterFrame` instead.
@main
final class Guides: Sketch {
    override func setup() {
        extend(RegistrationGuides())
    }

    override func draw() {
        background(.white)
        // A dot orbiting the center — just something for the guides to sit over.
        noStroke()
        fill(Color(red: 0.1, green: 0.5, blue: 0.9))
        let r = shortSide * 0.28
        drawCircle(width / 2 + cos(time) * r, height / 2 + sin(time) * r, 64 * scale)
    }
}

/// Draws an inset border and a center crosshair over whatever the sketch drew.
final class RegistrationGuides: SketchExtension {
    func afterDraw(_ sketch: Sketch) {
        sketch.withState {
            let inset = 40 * sketch.scale
            sketch.noFill()
            sketch.stroke(Color(white: 0, alpha: 0.25))
            sketch.strokeWeight(2 * sketch.scale)
            sketch.drawRect(corner: Vector2(inset, inset),
                            width: sketch.width - inset * 2,
                            height: sketch.height - inset * 2)
            sketch.drawLine(sketch.width / 2, inset, sketch.width / 2, sketch.height - inset)
            sketch.drawLine(inset, sketch.height / 2, sketch.width - inset, sketch.height / 2)
        }
    }
}
