import Ollin

/// Circle packing: fill the canvas with circles that grow until they touch,
/// never overlapping. `packCircles(count:)` scatters its own seeds and grows a
/// circle at each to the largest it can be without hitting a neighbor, so big
/// circles land first and smaller ones fill the gaps, the dense, varied look.
///
/// The packing is computed once and held (it's a pure function of the seed, so
/// the same seed always lays the circles down the same way); what moves is a
/// slow flow field that breathes color and a gentle wobble through the discs,
/// so the arrangement shimmers without the circles jumping around.
///
/// The output is ordinary `[Circle]`, so it feeds anything: here they're filled
/// and outlined, but the same set drops straight into the shape booleans,
/// hatching, or SVG export for the pen plotter.
@main
final class CirclePacking: Sketch {
    private var circles: [Circle] = []

    override func draw() {
        if circles.isEmpty {
            seed(11)
            circles = packCircles(count: 900,
                                  minRadius: 4 * scale,
                                  maxRadius: 110 * scale,
                                  padding: 3 * scale)
        }

        background(Color(hex: 0x0E1116))

        let ink = Color(hex: 0xF2C14E)
        let accent = Color(hex: 0xE86A5B)
        strokeWeight(1.5 * scale)

        for c in circles {
            // A slow field swells the color across neighbors and nudges each
            // disc a couple of pixels, so the whole pack breathes together.
            let flow = signedNoise(c.x * 0.0016, c.y * 0.0016, time * 0.4)
            let wobble = Vector2(signedNoise(c.y * 0.003, time * 0.6),
                                 signedNoise(c.x * 0.003, time * 0.6 + 19)) * (3 * scale)
            let tint = Color.mix(ink, accent, t: (flow + 1) * 0.5)
            var body = tint
            body.alpha = 0.85
            fill(body)
            stroke(tint)
            drawCircle(center: c.center + wobble, radius: c.radius)
        }
    }
}
