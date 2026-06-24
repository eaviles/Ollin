import Ollin

/// Accumulation — the canvas isn't cleared each frame, so faint marks pile up on
/// a persistent surface and the image is *built up over time* rather than redrawn.
/// `noClear()` turns it on; `blendMode(.add)` makes the marks sum as light. The
/// two together are the basis of "sandpainting" depth-of-field rendering: a form
/// is drawn as a haze of dim accumulated samples, and the blur is *earned* by
/// scattering each sample by how far it sits from the focal plane — not faked with
/// a post-process blur.
///
/// Here a slowly turning shell of points is sampled a few thousand times a frame.
/// Each sample is jittered within a disc whose radius grows with the point's
/// distance from a sweeping focal plane, so in-focus points stay crisp while
/// out-of-focus ones spread into soft bokeh as the accumulation fills them in. The
/// shell keeps turning so light flows across the canvas instead of saturating to
/// white, and the focus racks slowly back and forth so every depth has its moment.
///
/// Try commenting out `noClear()`: you'll see a single frame's sparse, jittered
/// scatter — proof that the soft, dense picture is entirely the accumulation at
/// work.
@main
final class Accumulation_Example: Sketch {
    private struct Point3 {
        var x, y, z: Double      // position on the unit shell
        var tone: Double         // 0…1 color key (by height)
    }
    private var points: [Point3] = []

    override func setup() {
        seed(11)
        background(Color(red: 0.02, green: 0.015, blue: 0.03))   // the one base wipe
        noClear()                                                // then accumulate forever

        // A wobbly spherical shell of points (a noise-displaced sphere). Uniform
        // directions via the z-uniform method, displaced by 3D noise so the form
        // has a little surface relief as it turns.
        for _ in 0 ..< 4000 {
            let height = random(-1, 1)               // uniform over the sphere
            let phi = random(.tau)
            let band = (1 - height * height).squareRoot()
            var dx = band * cos(phi)
            var dy = height
            var dz = band * sin(phi)
            let wobble = 1 + 0.16 * noise(dx * 1.4 + 3, dy * 1.4 + 7, dz * 1.4 + 1)
            dx *= wobble; dy *= wobble; dz *= wobble
            points.append(Point3(x: dx, y: dy, z: dz, tone: (height + 1) / 2))
        }
    }

    override func draw() {
        blendMode(.add)          // every sample adds light to the pile
        noStroke()

        let cx = width / 2, cy = height / 2
        let radius = min(width, height) * 0.34
        let angle = time * 0.25                      // a slow turn around the vertical axis
        let cosA = cos(angle), sinA = sin(angle)

        let focus = sin(time * 0.35) * 0.9           // the focal plane sweeps the depth range
        let blurStrength = radius * 0.22             // bokeh spread per unit of defocus
        let samplesPerPoint = 2

        for p in points {
            // Rotate (x, z) around the vertical axis, then orthographic-project.
            let rx = p.x * cosA + p.z * sinA
            let rz = -p.x * sinA + p.z * cosA
            let screenX = cx + rx * radius
            let screenY = cy - p.y * radius

            let defocus = abs(rz - focus)            // distance from the focal plane
            let blur = defocus * blurStrength
            // Sharp points are small and bright; defocused ones dim as their light
            // spreads over a wider disc (energy roughly conserved).
            let dotSize = (0.8 + defocus * 1.0) * scale
            let alpha = 0.11 / (1 + defocus * 6)

            let base = Colormap.magma.color(at: 0.25 + p.tone * 0.6)
            fill(Color(red: base.red, green: base.green, blue: base.blue, alpha: alpha))

            for _ in 0 ..< samplesPerPoint {
                let j = ring(innerRadius: 0, outerRadius: blur)
                drawCircle(screenX + j.x, screenY + j.y, dotSize)
            }
        }
    }
}
