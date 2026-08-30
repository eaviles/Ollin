import Ollin

/// Gradient paint on a composed SDF field: a linear or radial `fill` (or `stroke`)
/// paints the whole *merged* region by position, as one continuous surface, not
/// per-leaf, so the ramp flows unbroken across a smooth-union seam where the
/// individual shapes' own colors would otherwise meet and melt. (Along-path has no
/// single path on a merged field, so it isn't supported there.)
///
/// Set the gradient with the same `fill(.linear/.radial(...))` / `stroke(...)` you'd
/// use on any shape, then `drawSDF` the field. Try swapping `.linear` for `.radial`,
/// moving the endpoints, or changing each `k` (how much the shapes melt).
@main
final class CombinatorsGradient: Sketch {
    let warm = Ramp([Color(hex: 0xFFF3C4), Color(hex: 0xFF8A3D), Color(hex: 0xD81E5B)])
    let cool = Ramp(stops: [(0.0, Color(hex: 0x2BD9C0)), (0.5, Color(hex: 0x3A86FF)),
                            (1.0, Color(hex: 0x7B2FF7))], in: .oklch)

    override func draw() {
        background(Color(white: 0.06))
        let t = time

        // 1) Linear fill across a melted blob: a circle, a rounded rect, and a bump
        //    smooth-union into one region; the warm ramp sweeps across the whole thing
        //    as a single surface (the seams don't break it). The melt amount breathes.
        let k = 26 + unipolar(sin(t)) * 70
        let blob = SDF.circle(radius: 120)
            .smoothUnion(SDF.rect(width: 210, height: 120, cornerRadius: 28).at(135, 12), k: k)
            .smoothUnion(SDF.circle(radius: 72).at(44, 124), k: k)
        withState {
            translate(width * 0.32, height * 0.34)
            noStroke()
            fill(.linear(from: Vector2(-170, -150), to: Vector2(210, 170), warm))
            drawSDF(blob)
        }

        // 2) Radial fill on a mandala: one petal on the +x axis (the canonical wedge for
        //    `repeatedRadially`) repeated around the origin, filled by a radial ramp
        //    centered on the field — the color rings out evenly through every copy,
        //    because the gradient is sampled in field space, not per shape.
        withState {
            translate(width * 0.71, height * 0.34)
            rotate(t * 0.3)
            noStroke()
            fill(.radial(center: .zero, radius: 215, cool))
            let petal = SDF.ellipse(radiusX: 92, radiusY: 28).at(128, 0)
                .smoothUnion(SDF.circle(radius: 30).at(172, 0), k: 22)
                .repeatedRadially(count: 9)
            drawSDF(petal)
        }

        // 3) Gradient *stroke* on a merged outline: no fill, the warm ramp traced left→
        //    right along the melted contour of two discs and a bar.
        withState {
            translate(width * 0.5, height * 0.74)
            noFill()
            stroke(.linear(from: Vector2(-230, 0), to: Vector2(230, 0), warm))
            strokeWeight(9)
            let bar = SDF.circle(radius: 70).at(-155, 0)
                .smoothUnion(SDF.rect(width: 210, height: 46, cornerRadius: 23), k: 44)
                .smoothUnion(SDF.circle(radius: 70).at(155, 0), k: 44)
            drawSDF(bar)
        }

        drawCaption("Gradient paint on a merged SDF field: linear fill · radial fill · gradient stroke")
    }
}
