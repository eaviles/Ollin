import Ollin

/// Continuous shape packing: instead of filling the canvas in one pass, a few
/// shapes are added every frame, each grown to the largest that fits the gaps
/// left by the shapes already down. Big gaps fill first, so each new shape is
/// smaller than the last, and the canvas densifies from a handful of large
/// shapes to a scatter of tiny ones, never overlapping.
///
/// It rides accumulation (`noClear()`): a placed shape never moves, so each frame
/// draws only the *new* shapes onto the persistent canvas, and the per-frame cost
/// stays flat however full it gets. With a shape bag the fit is measured against
/// each neighbor's *outline*, not its bounding circle, so small shapes settle into
/// a star's notches instead of being held off at arm's length.
///
/// Click or press a key for the one-call form: `packShapes` runs the same
/// packing to completion in one shot, a fresh seeded variation on every press,
/// the way you'd pack a poster or a plotter file rather than watch it fill.
/// Another press grows a new pack live again. The output either way is
/// ordinary geometry, plotter-friendly like the rest of the packing family.
@main
final class ShapePacking: Sketch {
    private var packer: ContinuousPacking?
    private var oneShot: [Shape] = []
    private var showingOneShot = false
    private var packSerial = 0

    private lazy var bag: [Shape] = [polygon(3), polygon(4), polygon(5),
                                     polygon(6), polygon(5, star: true)]

    private func polygon(_ sides: Int, star: Bool = false) -> Shape {
        let count = star ? sides * 2 : sides
        let points = (0 ..< count).map { i -> Vector2 in
            let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
            let r = (star && i % 2 == 1) ? 0.46 : 1.0
            return Vector2(cos(a) * r, sin(a) * r)
        }
        return Shape(points, closed: true)
    }

    override func setup() {
        noClear()
    }

    override func draw() {
        if showingOneShot {
            drawOneShot()
        } else {
            drawContinuous()
        }
    }

    private func drawContinuous() {
        if packer == nil {
            background(Color(hex: 0x11121A))
            packer = ContinuousPacking(shapes: bag, in: bounds, seed: 4,
                                       minRadius: 3 * scale, maxRadius: 130 * scale,
                                       padding: 4 * scale, scale: 0.9, attemptsPerStep: 14)
        }
        guard let packer else { return }

        // Add a few shapes, then draw only the ones just placed; the rest persist
        // on the accumulated canvas.
        let start = packer.count
        packer.step()

        noStroke()
        for i in start ..< packer.count {
            fill(inkColor(at: packer.circles[i].center))
            drawShape(packer.shapes[i])
        }
    }

    private func drawOneShot() {
        // Opaque fills over a repainted background, so redrawing the held pack
        // each frame is idempotent on the accumulated canvas.
        background(Color(hex: 0x11121A))
        noStroke()
        for shape in oneShot {
            let c = shape.contours.first?.points.centroid ?? center
            fill(inkColor(at: c))
            drawShape(shape)
        }
        drawCaption("packShapes in one call, pack \(packSerial); click or press a key to grow one live again")
    }

    private func inkColor(at point: Vector2) -> Color {
        let t = noise(point.x * 0.0016, point.y * 0.0016)
        return Color.mix(Color(hex: 0x6FD3C7), Color(hex: 0xF2799E), t)
    }

    override func mousePressed() { toggle() }
    override func keyPressed() { toggle() }

    private func toggle() {
        showingOneShot.toggle()
        if showingOneShot {
            packSerial += 1
            seed(4 + packSerial)
            oneShot = packShapes(bag, count: 420,
                                 minRadius: 4 * scale, maxRadius: 130 * scale,
                                 padding: 4 * scale, scale: 0.9)
        } else {
            packer = nil   // restart the live pack on a fresh canvas
        }
    }
}
