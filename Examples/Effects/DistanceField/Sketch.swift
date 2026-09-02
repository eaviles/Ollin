import Ollin

/// **Measured distance fields**: a few marks drawn into a layer, and then a question
/// asked of every pixel in it. How far is the nearest edge, and which way is it?
///
/// `.distanceField` answers both at once. Its red channel is the distance in pixels,
/// negative inside a shape, and its green and blue are the direction to that nearest
/// edge, so `pixel + direction * abs(distance)` is the edge point itself. Everything
/// here is one of those two answers read back:
///
/// - **rings**: the distance mapped through a repeating ramp, so equal distances share a
///   color and the marks wear contour lines like a map.
/// - **grown**: the distance cut at one value, which grows the shapes by that much (or
///   shrinks them, if you ask for a negative one) and melts neighbors into each other.
/// - **cells**: the direction followed to its edge, and the color found there brought
///   back. Every pixel takes the color of the mark nearest it, which is a Voronoi
///   diagram of the shapes themselves rather than of a set of points.
///
/// Try it: drag the `grow` parameter through zero in the `grown` reading and watch the blobs
/// meet, or slow `spacing` down until the rings crowd.
@main
final class DistanceField_Example: Sketch {

    enum Reading: String, CaseIterable, ParamOption { case together, rings, grown, cells }

    @Param(style: .segmented, icon: "square.stack.3d.down.right") var reading: Reading = .together
    @Param(-40 ... 90, icon: "circle.dashed") var grow = 26.0
    @Param(12 ... 120, icon: "circle.circle") var spacing = 46.0

    let ground = Color(hex: 0x121A22)
    let inks = [Color(hex: 0xE8734A), Color(hex: 0x49B0A5), Color(hex: 0xE0C25C),
                Color(hex: 0xC85A7C), Color(hex: 0x6E8FD4)]

    override func draw() {
        background(ground)

        // The marks. Nothing here knows about the field: it is an ordinary layer, drawn
        // the ordinary way, and the field is measured off it afterward.
        let marks = makeRenderTarget()
        withTarget(marks) {
            noStroke()
            for (i, ink) in inks.enumerated() {
                let phase = Double(i) * 1.7
                let x = width * 0.5 + cos(time * 0.23 + phase) * width * 0.27
                let y = height * 0.5 + sin(time * 0.31 + phase * 1.3) * height * 0.24
                fill(ink)
                drawCircle(x, y, 44 + Double(i) * 13)
            }
            // A stroked path measures just as well as a filled shape: the field cares
            // about coverage, not about how it got there.
            stroke(inks[1])
            strokeWeight(10)
            noFill()
            let arc = stride(from: 0.1, through: 0.9, by: 0.02).map { t in
                Vector2(width * t, height * 0.8 + sin(t * 7 + time * 0.5) * height * 0.06)
            }
            drawPolyline(arc)
        }

        let field = marks.filtered(.distanceField())

        switch reading {
        case .rings:
            drawImage(field.filtered(.fieldMap(contours, from: 0, to: spacing,
                                               repeating: true)).image, 0, 0)
        case .grown:
            drawImage(field.filtered(.fieldMap(Ramp([inks[4], ground]),
                                               from: grow, to: grow + 1.5)).image, 0, 0)
            drawImage(marks.image, 0, 0)
        case .cells:
            drawImage(field.combined(with: marks, .shader(Shader(nearestMark))).image, 0, 0)
        case .together:
            // Two readings of one field, one over the other: the cells give the color,
            // the rings darken it every `spacing` pixels out from each edge.
            drawImage(field.combined(with: marks, .shader(Shader(nearestMark))).image, 0, 0)
            blendMode(.multiply)
            drawImage(field.filtered(.fieldMap(shading, from: 0, to: spacing,
                                               repeating: true)).image, 0, 0)
            blendMode(.normal)
            drawImage(marks.image, 0, 0)
        }
    }

    /// A ramp that starts dark at every edge and fades out: repeated, it reads as the
    /// contour lines of a map, one line for each `spacing` pixels of distance.
    var contours: Ramp {
        Ramp(stops: [(0, Color(hex: 0xF3EDE2)), (0.06, Color(hex: 0x2B3947)),
                     (0.14, Color(hex: 0xF3EDE2)), (1, Color(hex: 0xB9C4CE))])
    }

    /// The same shape, kept pale, so multiplying it over the cells shades them instead
    /// of painting them.
    var shading: Ramp {
        Ramp(stops: [(0, Color(white: 1)), (0.08, Color(white: 0.55)),
                     (0.2, Color(white: 1)), (1, Color(white: 0.86))])
    }

    /// Follow the direction to the nearest edge, step a little past it so the lookup
    /// lands in the mark rather than on its soft rim, and bring that color back. Signing
    /// the overshoot is what makes one line serve both sides: from outside the shape the
    /// direction already points inward, and from inside it points out.
    ///
    /// `sampleRaw` is the reason this works: the ordinary `sample` reads a layer as a
    /// color, and a distance in pixels is not one.
    let nearestMark = """
    float4 shade(float2 uv, ShaderInfo info) {
        float4 field = sampleRaw(info, uv);
        float2 here = uv * info.resolution;
        float2 inside = here + field.gb * (abs(field.r) + 4.0 * sign(field.r));
        float4 mark = sampleAux(info, inside / info.resolution);
        // Fade the cell out the farther it is from its mark, so the picture keeps some
        // depth in it. Only the outside is faded: inside a mark the distance runs
        // negative, and darkening by it would put a smudge at the middle of every shape.
        float fade = 1.0 - clamp(max(field.r, 0.0) / 520.0, 0.0, 0.62);
        return float4(mark.rgb * fade, 1.0);
    }
    """
}
