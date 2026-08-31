import Ollin

/// Circle packing three ways, on one key. The default is the self-seeding
/// grow-to-touch pack: `packCircles(count:)` scatters its own seeds and grows
/// a circle at each to the largest it can be without hitting a neighbor, so
/// big circles land first and smaller ones fill the gaps, the dense, varied
/// look. Click or press a key for the other two: `packCircles(around:)` grows
/// a circle at each site of a blue-noise scatter in closed form (half the
/// distance to the nearest neighbor), the even foam; and `relaxCircles` starts
/// from a heavily overlapping crowd and pushes every overlapping pair apart
/// until none do, holding the radii you chose.
///
/// Each packing is computed once and held (all three are pure functions of the
/// seed, so the same seed always lays the circles down the same way); what
/// moves is a slow flow field that breathes color and a gentle wobble through
/// the discs, so the arrangement shimmers without the circles jumping around.
///
/// The output is ordinary `[Circle]`, so it feeds anything: here they're filled
/// and outlined, but the same set drops straight into the shape booleans,
/// hatching, or SVG export for the pen plotter.
@main
final class CirclePacking: Sketch {
    private enum Mode {
        case grow, foam, parted
    }

    private var mode = Mode.grow
    private var circles: [Circle] = []

    override func draw() {
        if circles.isEmpty {
            seed(11)
            switch mode {
            case .grow:
                circles = packCircles(count: 900,
                                      minRadius: 4 * scale,
                                      maxRadius: 110 * scale,
                                      padding: 3 * scale)
            case .foam:
                let sites = poissonDisk(radius: 46 * scale)
                circles = packCircles(around: sites, padding: 3 * scale)
            case .parted:
                // A crowd piled into the middle, radii chosen up front, then
                // parted until nothing overlaps; the radii never change.
                let crowd = (0 ..< 220).map { _ in
                    Circle(center: randomVector(in: Rectangle(center: center,
                                                              width: shortSide * 0.5,
                                                              height: shortSide * 0.5)),
                           radius: random(9, 52) * scale)
                }
                circles = relaxCircles(crowd, iterations: 120, padding: 2 * scale)
            }
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
            let tint = Color.mix(ink, accent, (flow + 1) * 0.5)
            var body = tint
            body.alpha = 0.85
            fill(body)
            stroke(tint)
            drawCircle(center: c.center + wobble, radius: c.radius)
        }

        drawCaption(caption)
    }

    override func mousePressed() { advance() }
    override func keyPressed() { advance() }

    private func advance() {
        switch mode {
        case .grow: mode = .foam
        case .foam: mode = .parted
        case .parted: mode = .grow
        }
        circles = []
    }

    private var caption: String {
        switch mode {
        case .grow:
            return "self-seeding grow-to-touch; click or press a key for the blue-noise foam"
        case .foam:
            return "a circle grown at each blue-noise site, the even foam; next, relaxed parting"
        case .parted:
            return "an overlapping crowd parted with its radii held; next, grow-to-touch"
        }
    }
}
