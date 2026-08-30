import Ollin

/// Blue-noise stippling: an even-but-organic scatter with no clumps and no
/// gaps. `poissonDisk(radius:)` lays down points no two closer than the radius
/// (Bridson's dart-throwing), the distribution that reads as *natural* coverage:
/// plain random scatter clusters and leaves holes, blue noise never does.
///
/// The layout is computed once and held (it's a pure function of the seed, so
/// the same seed always lays the dots down the same way); what moves is a slow
/// flow field that swells each dot's size and shifts its ink, so the field
/// breathes without the points jumping around.
///
/// The points are ordinary `[Vector2]`, so they feed anything: here they're
/// stippled as dots, but the same set drops straight into the tessellators for
/// strikingly even cells, with no Lloyd relaxation needed:
///
/// ```swift
/// let sites = poissonDisk(radius: 30)
/// for cell in voronoi(sites).cells { drawShape(cell) }
/// ```
@main
final class BlueNoise: Sketch {
    private var points: [Vector2] = []

    override func draw() {
        if points.isEmpty {
            seed(9)
            points = poissonDisk(radius: 22 * scale)
        }

        background(Color(hex: 0x11141C))

        let ink = Color(hex: 0xE8ECF4)
        let accent = Color(hex: 0x5AA9E6)
        noStroke()

        for p in points {
            // A flow field drives each dot's size and ink so neighbors swell and
            // fade together; a second, faster field nudges each dot a few pixels,
            // so the whole stipple shimmers while the coverage stays even.
            let flow = signedNoise(p.x * 0.0018, p.y * 0.0018, time * 0.5)
            let wobble = Vector2(signedNoise(p.y * 0.004, time * 0.8),
                                 signedNoise(p.x * 0.004, time * 0.8 + 42)) * (5 * scale)
            let size = (2.0 + (flow + 1) * 2.8) * scale
            fill(Color.mix(ink, accent, (flow + 1) * 0.5))
            drawCircle(center: p + wobble, radius: size)
        }
    }
}
