import Ollin

/// SDF combinators: compose signed-distance *fields* so shapes **merge** instead of
/// just stacking. A smooth union melts two shapes into one blob (their colors blending
/// across the seam), subtraction carves one out of another, and morph blends between
/// two shapes. Domain ops (`repeated`, `mirrored`) tile or fold the whole field.
///
/// Build a field with the `SDF` value type and draw it with `drawSDF`. Unlike the
/// immediate `drawCircle`/`drawRect` calls (each its own shape), a composed `SDF`
/// fills as a single region, and a stroke would trace the *merged* outline.
///
/// Try it: change each `k` (how much the shapes melt), swap `.smoothUnion` for
/// `.smoothSubtract`, the `.morph` amount, or `.repeated(...)` for `.mirrored()`.
@main
final class Combinators_Example: Sketch {
    override func draw() {
        background(Color(white: 0.07))
        noStroke()
        let t = time

        // 1) Melt: a circle and a rounded rect smooth-union; their colors blend at the
        //    seam. A second circle is smoothly *subtracted* to carve a hole. The melt
        //    amount breathes.
        let k = 20 + (sin(t) * 0.5 + 0.5) * 80
        let melt = SDF.circle(radius: 130).colored(Color(hex: 0xff5470))
            .smoothUnion(
                SDF.rect(width: 230, height: 130, cornerRadius: 24)
                    .colored(Color(hex: 0x3a86ff))
                    .at(x: 120, y: 0),
                k: k)
            .smoothSubtract(SDF.circle(radius: 50).at(x: -80, y: -10), k: 18)
            .at(x: width * 0.30, y: height * 0.36)
        drawSDF(melt)

        // 2) Morph: a six-point star into a circle and back, scaled by a breath, spinning.
        let amount = sin(t * 0.8) * 0.5 + 0.5
        let morph = SDF.star(outerRadius: 120, innerRadius: 54, points: 6)
            .colored(Color(hex: 0xffd166))
            .morph(SDF.circle(radius: 110).colored(Color(hex: 0x06d6a0)), amount: amount)
            .scaled(0.85 + 0.15 * (sin(t * 1.3) * 0.5 + 0.5))
            .rotated(t * 0.5)
            .at(x: width * 0.70, y: height * 0.36)
        drawSDF(morph)

        // 3) Scoped block sugar: bare draw calls inside a block merge (the same fields
        //    as the value type, layered over `drawSDF`). Here a `repeated` block tiles
        //    a little melted cell (a rounded square + a bump) into a row.
        withState {
            translate(width * 0.5, height * 0.74)
            fill(Color(hex: 0xbdb2ff))
            let bump = 30 + sin(t * 2) * 14
            repeated(spacing: Vector2(165, 0), count: 3) {
                smoothUnion(k: 14) {
                    drawRect(-30, -30, 60, 60, cornerRadius: 16)
                    drawCircle(bump, 0, 22)
                }
            }
        }

        drawCaption("SDF combinators: smooth union + color melt · morph · scoped block + tiling")
    }
}
