import Ollin

/// Volumes: a plume of smoke rising over a pedestal, a ball hanging in it, and
/// a lamp above throwing the ball's shadow down through the smoke.
///
/// The smoke is a `Volume`, a box of density samples. Once, in `setup()`, a
/// grid of fractal noise is filled that repeats from its bottom row to its top
/// (`fbm(_:_:loop:radius:)` with the height as the loop), and every frame the
/// plume reads that grid scrolled upward and shapes it into a column that
/// widens and thins as it rises. The scroll comes back to where it started
/// every twelve seconds, so the plume rises without end and an export loops.
/// `drawVolume` marches each pixel's ray through the box after the solids are
/// drawn, reading their depth: the ball inside the plume is veiled only by the
/// smoke in front of it and hides the smoke behind it. Along the ray the smoke
/// takes light away (Beer's law) and gives back the lamp's light and the
/// ambient it scatters toward the eye; the lamp's light reaching each point has
/// crossed the smoke between, so the plume shades itself, and the ball's
/// shadow cuts a dark shaft down through it.
///
/// The `medium` parameter says what the plume is made of: gray `smoke`, a white
/// `cloud` that scatters nearly everything, `fire` glowing from inside, `ink`
/// that only darkens, a faint violet `nebula`. `thickness` scales the medium's
/// density, and the lamp can be swung around above the plume.
@main
final class Volumes: Sketch {

    @Param var medium: Medium = .smoke
    @Param(0.2 ... 3, icon: "aqi.medium", group: "Smoke") var thickness = 1.0
    @Param(0 ... 6.28, icon: "lamp.desk", group: "Lamp") var lampAround = 0.8

    /// The plume's grid, and the repeating noise it is read from.
    private let columns = 36, rows = 48
    private var source = Volume(width: 2, height: 2, depth: 2)

    override func setup() {
        // Noise over the box's width and depth, looping over its height: the
        // bottom row and the top row hold the same values, so a read scrolled
        // past the top wraps to the bottom without a seam.
        noiseSeed(4)
        source = Volume(width: columns, height: rows, depth: columns) { u, v, w in
            fbm(u * 3.4, w * 3.4, loop: v, radius: 0.7, octaves: 4)
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1014))
        toneMap(.aces)
        cameraShowcase(.turntable(period: 48), target: Vector3(0, 2.5, 0),
                       radius: 7.6, elevation: 0.14, fieldOfView: .pi / 4)
        // Each temporal sample starts the march at its own offsets, so the
        // resolve averages the march's fine grain away.
        temporalAntialiasing()

        ambientLight(Color(hex: 0x1B2230))
        castShadows()
        let lamp = Vector3(cos(lampAround) * 1.1, 6.4, sin(lampAround) * 1.1)
        spotLight(Color(hue: 0.08, saturation: 0.3, brightness: 1), at: lamp,
                  direction: Vector3(0, 1.5, 0) - lamp, coneAngle: 0.42, penumbra: 0.35,
                  intensity: 2.4)

        noStroke()
        fill(Color(hex: 0x3A3F47))
        drawGround(size: 20)
        withState {
            translate(0, 0.35, 0)
            fill(Color(hex: 0x6E737B))
            drawCylinder(radius: 0.55, height: 0.7)
        }
        // The ball hangs inside the plume, below the lamp.
        withState {
            translate(0.1, 3.0 + sin(time * 0.6) * 0.12, 0.05)
            fill(Color(hex: 0xC9A27A))
            drawSphere(radius: 0.2)
        }

        // The plume: the repeating noise scrolled up one grid height every
        // twelve seconds, kept where it rises above a floor that climbs away
        // from the column's axis, so the smoke frays at its edge instead of
        // ending on the box's faces.
        let rise = (time / 12).truncatingRemainder(dividingBy: 1)
        let plume = Volume(width: columns, height: rows, depth: columns) { u, v, w in
            let scrolled = (v - rise + 1).truncatingRemainder(dividingBy: 1)
            let spread = 0.16 + 0.24 * v
            let fromAxis = Vector2(u - 0.5, w - 0.5).length / spread
            let floor = 0.42 + 0.35 * fromAxis * fromAxis + 0.15 * v
            let ends = min(1, v * 10) * min(1, (1 - v) * 2.5)
            return max(0, source.value(u: u, v: scrolled, w: w) - floor) * 5 * ends
        }
        var look = medium
        look.density *= thickness
        withState {
            translate(0, 0.7 + 2.1, 0)
            drawVolume(plume, width: 2.8, height: 4.2, depth: 2.8, medium: look)
        }

        withOverlay { drawCaption("Volumes: smoke from repeating noise, lit and shadowed") }
    }
}
