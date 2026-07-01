import Ollin

/// Continuous shape packing: instead of filling the canvas in one pass, a few
/// shapes are added every frame, each grown to the largest that fits the gaps
/// left by the shapes already down. Big gaps fill first, so each new shape is
/// smaller than the last, and the canvas densifies from a handful of large
/// shapes to a scatter of tiny ones, never overlapping.
///
/// It rides accumulation (`noClear()`): a placed shape never moves, so each frame
/// draws only the *new* shapes onto the persistent canvas, and the per-frame cost
/// stays flat however full it gets. `ContinuousPacking` packs each shape's
/// bounding circle, so the output is ordinary geometry, plotter-friendly like the
/// rest of the packing family.
@main
final class ShapePacking: Sketch {
    private var packer: ContinuousPacking?

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
        if packer == nil {
            background(Color(hex: 0x11121A))
            let bag = [polygon(3), polygon(4), polygon(5), polygon(6), polygon(5, star: true)]
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
        let ink = Color(hex: 0x6FD3C7), accent = Color(hex: 0xF2799E)
        for i in start ..< packer.count {
            let c = packer.circles[i].center
            let t = (signedNoise(c.x * 0.0016, c.y * 0.0016) + 1) * 0.5
            fill(Color.mix(ink, accent, t: t))
            drawShape(packer.shapes[i])
        }
    }
}
