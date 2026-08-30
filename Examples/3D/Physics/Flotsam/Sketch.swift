import Ollin
import OllinPhysics

/// A harbor after a spill. Crates of every weight ride the swell at their own
/// depth, a stone anchor sits on the bottom, and the current carries the lot
/// slowly past. **Drag** a crate under and let go to watch it surface.
///
/// The water showcase for `World3D`. Nothing here opts in to floating:
/// `world.water` is one property, like `ground`, and everything already in the
/// world starts riding it. How deep each crate sits is not tuned, it is the
/// `density` it was built with, so the pale light ones ride high and the dark
/// heavy ones are almost under. `waterMesh` hands back the very surface the
/// bodies are floating on, so the drawn swell and the ridden swell are the
/// same one.
@main
final class Flotsam: Sketch {
    let world = World3D()
    var grip: Joint3D?

    /// How high the swell runs, in world units.
    @Param(0 ... 0.5, icon: "water.waves") var swell = 0.22
    /// The current carrying everything along, in units per second.
    @Param(-1.5 ... 1.5, icon: "arrow.right") var current = 0.35
    /// How heavy the water is. Brine floats the same crates higher.
    @Param(0.7 ... 1.6, icon: "drop") var brine = 1.0

    /// One floating thing, kept so the same numbers build it and draw it.
    struct Crate {
        var body: Body3D
        var size: Vector3
        var color: Color
    }
    var crates: [Crate] = []
    var anchor: Body3D?

    let seaLevel = 0.0
    let deep = -6.0

    override func setup() {
        // The sea floor, deep enough that what sinks is clearly gone.
        world.ground = deep
        world.water = Water(level: seaLevel, waves: Water.Waves(amplitude: swell,
                                                                wavelength: 7,
                                                                speed: 1.6))
        buildCrates()
        buildAnchor()
    }

    /// Six crates from cork to nearly waterlogged. The only thing that differs
    /// between them is `density`, which is what decides where each waterline
    /// lands: the lightest sits a fifth under, the heaviest nine tenths.
    func buildCrates() {
        let densities = [0.2, 0.35, 0.5, 0.65, 0.8, 0.92]
        for (index, density) in densities.enumerated() {
            let size = Vector3(0.8, 0.8, 0.8)
            let x = Double(index) * 1.25 - 3.1
            let body = world.addBody(.box(width: size.x, height: size.y,
                                          depth: size.z),
                                     at: Vector3(x, 2.2 + Double(index) * 0.35,
                                                 random(-0.7, 0.7)),
                                     rotated: random(-0.4, 0.4),
                                     axis: Vector3(0.2, 1, 0.3),
                                     density: density, friction: 0.6)
            // Heavy reads dark, light reads bleached, so the row is a legend
            // for its own waterlines.
            let color = Color.mix(Color(hex: 0xF2E3C6), Color(hex: 0x6B4A2F),
                                  (density - 0.2) / 0.72)
            crates.append(Crate(body: body, size: size, color: color))
        }
    }

    /// A stone heavier than water, to show what the same water does to
    /// something it cannot hold up.
    func buildAnchor() {
        anchor = world.addBody(.box(width: 0.7, height: 0.7, depth: 0.7),
                               at: Vector3(2.6, 2.0, 1.4), rotated: 0.5,
                               axis: Vector3(1, 0.4, 0), density: 3.2,
                               friction: 0.9)
    }

    override func mousePressed() {
        grip = grabBody(at: mouse, in: world)
    }

    override func mouseReleased() {
        grip?.remove()
        grip = nil
    }

    override func draw() {
        background(Color(hex: 0x0B1520))
        // An open sky rather than one of the bundled interiors: it is what the
        // water has to reflect for a swell to read as water at all.
        environment(.sky(turbidity: 3.2, sunElevation: 0.95))
        // The sky alone is a soft blue dome, which leaves the cargo gray. A
        // warm key gives the crates their own color back and tells the light
        // in the scene where the sun is.
        lightingPreset(.goldenHour)
        castShadows()
        cameraShowcase(.autoOrbit(period: 40), from: Camera3D
            .perspective(eye: Vector3(0.6, 5.4, 8.6), target: Vector3(0, -0.3, 0)))

        // The knobs reach the water between steps, so a rising swell picks the
        // crates up as you drag it.
        world.water?.waves?.amplitude = swell
        world.water?.flow = Vector3(current, 0, 0)
        world.water?.density = brine

        if let grip { dragGrab(grip, to: mouse) }
        world.advance(by: deltaTime)
        keepInFrame()

        drawSea()
        drawCargo()
        drawCaption("drag a crate under and let go")
    }

    /// The current would carry everything out of shot in a minute, so the whole
    /// drift wraps around: anything past the far side comes back on the near
    /// one, still at the height it was riding.
    func keepInFrame() {
        let edge = 6.0
        for crate in crates {
            let at = crate.body.position
            guard abs(at.x) > edge else { continue }
            let wrapped = at.x > 0 ? at.x - 2 * edge : at.x + 2 * edge
            crate.body.position = Vector3(wrapped, at.y, at.z)
        }
    }

    /// The sea is drawn from the same surface the crates are floating on, so
    /// the waterline you see is the waterline they are holding.
    func drawSea() {
        guard let surface = world.waterMesh(extent: 40, resolution: 110) else { return }
        fill(Color(hex: 0x2C7C96))
        // Rough rather than mirror-smooth, and not only for the look: a
        // near-perfect mirror reflects the environment's lower half wherever a
        // wave tilts the reflection below the horizon, which lays flat gray
        // patches along the troughs. A little roughness blurs that boundary
        // away, and a sea this size is not a mirror anyway.
        material(.dielectric(roughness: 0.3))
        drawMesh(surface)

        // The floor, far enough down to read as depth rather than a lid.
        fill(Color(hex: 0x0E1A24))
        material(.dielectric(roughness: 0.95))
        withState {
            translate(0, deep, 0)
            drawBox(width: 84, height: 0.2, depth: 84)
        }
    }

    func drawCargo() {
        material(.dielectric(roughness: 0.6))
        for crate in crates {
            fill(crate.color)
            withBody(crate.body) {
                drawBox(width: crate.size.x, height: crate.size.y,
                        depth: crate.size.z)
            }
        }
        if let anchor {
            fill(Color(hex: 0x3B3F45))
            material(.dielectric(roughness: 0.8))
            withBody(anchor) {
                drawBox(width: 0.7, height: 0.7, depth: 0.7)
            }
        }
    }
}
