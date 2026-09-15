import Ollin

/// A courtyard at night with sixty-four lamps in it.
///
/// Forward lighting shades every pixel against every light, which is why the
/// inline set stops at eight: past that, the cost of a lit pixel is the size of the
/// room's lighting plan. This scene has sixty-four lamps and still runs, because
/// each one is given a `reach` (the distance past which it lights nothing at all)
/// and the renderer works out, one square of the screen at a time, which lamps
/// can arrive there. A pixel then shades against the four or five lamps
/// standing over it rather than the sixty-four in the courtyard.
///
/// The `reach` does as much for the look as it does for the speed. With no reach a
/// point light carries forever, so sixty-four of them are one flat wash and the courtyard
/// has no night left in it. With one, each lamp owns a pool of floor, the pools
/// overlap at their edges the way real lamps do, and the dark between them is what
/// makes the picture read. Drag **reach** and watch it happen: at the low end the
/// lamps are fireflies, at the high end the courtyard floods and the individual
/// sources disappear into each other.
///
/// The blocks are a fixed grid, so what moves is the light. Each lamp drifts along
/// its own slow loop at its own height, which is what shows the pools sliding over
/// the corners and up the walls. **lamps** takes the count from one to a hundred
/// and twenty-eight: at eight and under the frame is on the inline path (the same
/// one every 3D sketch has always used) and above it the tile grid takes over, with
/// nothing to see at the crossing but one more lamp.
@main
final class ManyLights: Sketch {

    @Param(1...128, icon: "lightbulb")
    var lamps = 64

    @Param(3...50, icon: "circle.dotted")
    var reach = 11.0

    @Param(icon: "eye")
    var showLamps = true

    /// A flat white matcap for the lamp props: a matcap ignores the scene lighting,
    /// which is exactly what a glowing thing wants.
    private let bulb = Image(width: 1, height: 1, color: Color(white: 1.0))

    /// The courtyard: one block per cell, each with its own height and footprint.
    /// Fixed for the run, so everything that moves in the picture is light.
    private var blocks: [(position: Vector3, size: Vector3)] = []
    /// Each lamp's hue, the ellipse it drifts on, and where it started on it.
    private var lights: [(hue: Double, center: Vector3, radius: Vector2, phase: Double, rate: Double)] = []

    override func setup() {
        seed(7)
        let span = 11, step = 5.0
        for row in -span...span where row % 2 == 0 {
            for column in -span...span where column % 2 == 0 {
                let x = Double(column) * step * 0.5
                let z = Double(row) * step * 0.5
                let height = 0.8 + random(2.2) * (random() < 0.22 ? 2.4 : 1.0)
                let side = 2.2 + random(1.4)
                blocks.append((Vector3(x, height / 2, z), Vector3(side, height, side)))
            }
        }
        for _ in 0..<128 {
            lights.append((hue: random(),
                           center: Vector3(random(-24, 24), 1.2 + random(3.4), random(-24, 24)),
                           radius: Vector2(random(2.0, 7.0), random(2.0, 7.0)),
                           phase: random(.tau),
                           rate: random(0.06, 0.22) * (random() < 0.5 ? -1 : 1)))
        }
    }

    override func draw() {
        background(Color(hex: 0x05060A))
        // A whisper of ambient so a wall with no lamp near it is still a shape and
        // not a hole. Everything else in the picture is a lamp's own pool.
        ambientLight(Color(white: 0.022))

        camera(.perspective(eye: Vector3(sin(time * 0.05) * 46, 31, cos(time * 0.05) * 46),
                            target: Vector3(0, 1.5, 0), fieldOfView: .pi / 4.2))

        // The lamps. Each is a point light with a reach, so it lights the corner it
        // hangs over and nothing else; the pools slide as the lamps drift.
        for index in 0..<lamps {
            let lamp = lights[index]
            let angle = lamp.phase + time * lamp.rate
            let at = lamp.center + Vector3(cos(angle) * lamp.radius.x, 0, sin(angle) * lamp.radius.y)
            pointLight(Color(hue: lamp.hue, saturation: 0.75, brightness: 1.0),
                       at: at, intensity: 1.7, reach: reach)
        }

        // The courtyard floor and its blocks. A plain matte surface: what the picture
        // is about is where the light lands, so nothing here competes with it.
        fill(Color(white: 0.52))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 130, height: 0.1, depth: 130)
        }
        fill(Color(white: 0.64))
        for block in blocks {
            withState {
                translate(block.position)
                drawBox(width: block.size.x, height: block.size.y, depth: block.size.z)
            }
        }

        // The lamps themselves, so the pools have visible sources. A light is
        // invisible in every renderer; the little bulb is a prop drawn beside it.
        guard showLamps else { return }
        for index in 0..<lamps {
            let lamp = lights[index]
            let angle = lamp.phase + time * lamp.rate
            let at = lamp.center + Vector3(cos(angle) * lamp.radius.x, 0, sin(angle) * lamp.radius.y)
            withState {
                translate(at)
                fill(Color(hue: lamp.hue, saturation: 0.35, brightness: 1.0))
                matcap(bulb)
                drawSphere(radius: 0.16)
            }
        }
    }
}
