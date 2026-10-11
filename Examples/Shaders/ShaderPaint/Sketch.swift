import Ollin

/// A `Shader` as PAINT: `fill(shader)` and `stroke(shader)` run `shade` at every
/// pixel a shape covers, so a per-pixel program becomes a fill the shape clips
/// for you. Inside `shade`, `uv` runs 0...1 across the shape's own bounding box
/// (it turns with the shape), and `info` adds three fields: `position`, the
/// pixel in canvas points; `distance`, the signed distance to the shape's edge
/// in its own units (negative inside); and `along`, the fraction along a stroke.
///
/// Four uses of each: a disk whose rings count inward from its edge
/// (`distance`); a turning star striped in its own frame (`uv`); a ribbon whose
/// pulse travels its length while its ink fades toward the edges (`along` and
/// `distance` on a stroke); and a field of tiles that share one grain, read
/// from the canvas rather than from each tile (`position`). Every shape is an
/// ordinary draw call under an ordinary `fill` or `stroke`; the shader is the
/// paint.
@main
final class ShaderPaint_Example: Sketch {
    @Param(2...24) var rings = 9.0
    @Param(0.5...4) var grain = 1.6

    /// Rings counting inward from the edge: `info.distance` is 0 on the outline
    /// and grows negative toward the center, in the shape's own units. The
    /// sources are strings, and `draw()` builds a `Shader` from each with this
    /// frame's `params`; the pipeline is cached by the text, so only the numbers
    /// travel.
    private static let ringsSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float ring = -info.distance / param(info, 0);
        float band = 0.5 + 0.5 * cos(ring * 6.2831853 - info.time * 1.5);
        float3 deep = float3(0.09, 0.14, 0.42);
        float3 light = float3(0.98, 0.84, 0.46);
        return float4(mix(deep, light, smoothstep(0.35, 0.85, band)), 1.0);
    }
    """

    /// Stripes in the shape's own frame: `uv` spans the star's box, so the
    /// stripes turn with it under `rotate`.
    private let stripesShader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float s = fract((uv.x + uv.y) * 7.0 - info.time * 0.6);
        float3 a = float3(0.95, 0.33, 0.27);
        float3 b = float3(1.0, 0.92, 0.80);
        return float4(mix(a, b, step(0.5, s)), 1.0);
    }
    """)

    /// A stroke's two coordinates: a pulse travels `info.along` from the start of
    /// the ribbon to its end, and the ink thins toward the edges by `info.distance`,
    /// which runs across the stroke, zero on its centerline.
    private static let ribbonSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float pulse = 0.5 + 0.5 * cos((info.along - info.time * 0.25) * 6.2831853 * 3.0);
        float across = 1.0 - smoothstep(0.0, param(info, 0), abs(info.distance));
        float3 ink = mix(float3(0.16, 0.62, 0.58), float3(0.92, 0.98, 0.95), pulse);
        // Opaque, faded toward the ground by `across`: a translucent stroke would
        // composite twice where a tight bend folds its inner side over itself.
        return float4(mix(float3(0.08, 0.07, 0.10), ink, 0.3 + 0.7 * across), 1.0);
    }
    """

    /// One grain across many tiles: `info.position` is the canvas point, so the
    /// noise continues from tile to tile instead of restarting in each.
    private static let grainSource = """
    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = info.position / 1080.0 * 8.0 * param(info, 0);
        float n = fbm(float3(p, info.time * 0.1));
        float3 dark = float3(0.12, 0.10, 0.16);
        float3 pale = float3(0.58, 0.54, 0.52);
        return float4(mix(dark, pale, smoothstep(0.3, 0.75, n)), 1.0);
    }
    """

    override func draw() {
        background(Color(hex: 0x14121A))

        // The tiles first, so the other shapes sit over them: one field of grain
        // read from the canvas, cut into tiles by the gaps between them.
        noStroke()
        fill(Shader(Self.grainSource, params: [Float(grain)]))
        let cols = 6, rows = 6
        let gap = width * 0.012
        let cell = (width - gap * Double(cols + 1)) / Double(cols)
        for row in 0..<rows {
            for col in 0..<cols {
                let x = gap + Double(col) * (cell + gap)
                let y = gap + Double(row) * (cell + gap)
                drawRect(x, y, cell, cell, cornerRadius: cell * 0.12)
            }
        }

        // The disk: rings from its edge inward, each `rings` units wide.
        let radius = width * 0.21
        fill(Shader(Self.ringsSource, params: [Float(width / rings / 2)]))
        drawCircle(width * 0.3, height * 0.34, radius)

        // The star turns, and its stripes turn with it, since `uv` is its own.
        fill(stripesShader)
        withState {
            translate(width * 0.7, height * 0.36)
            rotate(time * 0.3)
            drawStar(0, 0, width * 0.19, width * 0.09, points: 5)
        }

        // The ribbon: a stroked curve whose paint reads along it and across it.
        noFill()
        strokeWeight(width * 0.05)
        strokeCap(.round)
        stroke(Shader(Self.ribbonSource, params: [Float(width * 0.018)]))
        let y = height * 0.76
        var points: [Vector2] = []
        for i in 0...48 {
            let t = Double(i) / 48
            let x = width * 0.08 + t * width * 0.84
            points.append(Vector2(x, y + sin(t * .pi * 3 + time) * height * 0.07))
        }
        drawPolyline(points)
    }
}
