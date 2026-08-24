import Ollin

/// A ring of lit windows falling into itself, without end.
///
/// The droste filter maps the ring between `inner` and the layer's edge onto a
/// straight strip, repeats the strip along its own length, and maps it back. That
/// is what puts a smaller copy of the picture inside the picture, with a smaller
/// copy inside that one, and so on. `zoom` slides the strip: at 1 the picture is
/// exactly back where it started, so the fall loops with nothing to hide.
///
/// `twist` is the Escher half. At 0 the copies are plain concentric rings; at 1 one
/// turn around the middle also steps one copy down in size, and the rings wind into
/// a single spiral. Hold the mouse to see the rings without the twist.
///
/// The scene is built so the join never shows: the windows sit well inside the ring,
/// and the ground is the same flat color where each copy ends and the next begins.
@main
final class Droste_Example: Sketch {
    override var loopDuration: Double? { 16 }

    private let palette = CosinePalette.rainbow

    override func draw() {
        background(.black)

        let scene = renderTarget()
        withTarget(scene) { paint() }

        let twist = mouseIsPressed ? 0.0 : 1.0
        drawImage(scene.filtered(.droste(inner: 0.42, twist: twist,
                                         zoom: loopProgress(over: 16) * 2,
                                         rotation: 0.12)).image,
                  in: canvasRectangle)

        drawCaption(mouseIsPressed
            ? "twist 0: the copies are plain concentric rings"
            : "one turn steps one copy down, so the rings wind into one spiral; hold the mouse to unwind it")
    }

    /// The picture the filter reads: a flat ground, a ring of lit windows, and a
    /// scatter of small lights, all held between 0.5 and 0.88 of the half-height so
    /// neither the inner edge of the ring nor the outer one falls on anything.
    private func paint() {
        seed(4)
        background(Color(hex: 0x0A0E1A))
        let middle = Vector2(width / 2, height / 2)
        let unit = height / 2

        // The windows, each turned to face the middle.
        let count = 14
        for i in 0 ..< count {
            let angle = Double(i) / Double(count) * .tau
            let place = middle + Vector2(cos(angle), sin(angle)) * unit * 0.69
            withState {
                translate(place)
                rotate(angle)
                noStroke()
                fill(palette.color(at: Double(i) / Double(count)))
                drawRect(center: .zero, width: unit * 0.2, height: unit * 0.13,
                         cornerRadius: unit * 0.02)
                fill(Color(white: 1, alpha: 0.85))
                drawRect(center: Vector2(unit * 0.035, 0), width: unit * 0.05,
                         height: unit * 0.05, cornerRadius: unit * 0.008)
            }
        }

        // A ring of small lights between the windows, and a few loose ones.
        noStroke()
        for i in 0 ..< count {
            let angle = (Double(i) + 0.5) / Double(count) * .tau
            fill(Color(hex: 0xFFE08A, alpha: 0.9))
            drawCircle(center: middle + Vector2(cos(angle), sin(angle)) * unit * 0.54,
                       radius: unit * 0.012)
        }
        for _ in 0 ..< 60 {
            let angle = random(.tau)
            let r = random(0.52, 0.86)
            fill(Color(white: 1, alpha: random(0.15, 0.6)))
            drawCircle(center: middle + Vector2(cos(angle), sin(angle)) * unit * r,
                       radius: unit * random(0.002, 0.005))
        }
    }
}
