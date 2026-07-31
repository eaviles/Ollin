import Ollin

/// Watercolor pigment from polygon deformation.
///
/// Three pigment pools share the sheet: each is a `Watercolor` base (one
/// irregular polygon wobbled into character), painted as dozens of
/// further-deformed copies at a few percent opacity. The layers interleave
/// pigment by pigment, so where pools overlap the inks glaze into mixed
/// hues instead of one paint covering the other. A final pass clips a
/// speckle of circles to the darkest pool, the granulating-texture trick.
///
/// A still image by design (`noLoop()`): the stacked concave fills are
/// setup-heavy, painted once. Each variation pours a fresh sheet.
@main
final class Watercolor_Example: Sketch {
    private let paper = Color(hex: 0xF7F3E8)

    override func setup() {
        noLoop()
    }

    override func draw() {
        background(paper)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation)))

        // Three pools, each its own base blob so each keeps one character.
        let pigments: [(center: Vector2, radius: Double, color: Color)] = [
            (Vector2(width * 0.38, height * 0.42), 300, Color(hex: 0x2B5D8A)),
            (Vector2(width * 0.62, height * 0.55), 270, Color(hex: 0xB0413E)),
            (Vector2(width * 0.48, height * 0.68), 230, Color(hex: 0xD9A441)),
        ]
        let pools = pigments.map { pigment in
            Watercolor(around: pigment.center, radius: pigment.radius,
                       using: &rng)
        }

        // Interleave the layers (a few of each pigment, round after round)
        // so overlaps glaze both ways instead of stacking one-then-other.
        noStroke()
        for _ in 0 ..< 12 {
            for (pool, pigment) in zip(pools, pigments) {
                fill(pigment.color.withAlpha(0.045))
                for _ in 0 ..< 3 {
                    drawShape(pool.layerShape(using: &rng))
                }
            }
        }

        // Granulating texture: a speckle field clipped to the first pool's
        // base outline, the pigment-settling look.
        withClip(Shape(pools[0].polygon)) {
            fill(Color(hex: 0x1E3D5C).withAlpha(0.08))
            for _ in 0 ..< 600 {
                let p = randomVector(in: canvasRectangle)
                drawCircle(p.x, p.y, random(1, 4))
            }
        }

        drawCaption("stacked translucent deformations of one polygon")
    }
}
