// figure: frame=600
//
// Guide listing (Chapter 25): buoyancyScale. Four identical crates settled on still
// water, differing only in the density each was built with, so how much of
// each one is left above the line is the answer the water worked out. Still
// water rather than a swell, so the waterline is one clean horizontal and the
// depths can be read off it. No random anywhere, so the settle replays
// identically.
import Ollin
import OllinPhysics

final class Floating: Sketch {
    let world = World3D()

    let densities = [0.2, 0.4, 0.6, 0.8]
    let size = 0.8
    let deep = -3.0
    var crates: [Body3D] = []

    override func setup() {
        world.ground = deep
        world.water = Water(level: 0)

        for (index, density) in densities.enumerated() {
            let x = Double(index) * 1.15 - 1.72
            crates.append(world.addBody(.box(width: size, height: size, depth: size),
                                        at: Vector3(x, 1.4, 0), density: density,
                                        friction: 0.6))
        }
    }

    override func draw() {
        background(Color(hex: 0x0C1622))
        environment(.sky(turbidity: 3.0, sunElevation: 0.9))
        lightingPreset(.goldenHour)
        castShadows()
        camera(.perspective(eye: Vector3(0, 0.85, 6.6),
                            target: Vector3(0, -0.05, 0), fieldOfView: .pi / 4))

        world.advance(by: 1.0 / 60)

        // The crates first, so they are already there for the water to cut.
        material(.dielectric(roughness: 0.6))
        for (index, crate) in crates.enumerated() {
            fill(Color.mix(Color(hex: 0xF2E3C6), Color(hex: 0x6B4A2F),
                           Double(index) / Double(densities.count - 1)))
            withBody(crate) {
                drawBox(width: size, height: size, depth: size)
            }
        }

        // The water is drawn from the surface the crates are floating on.
        if let surface = world.waterMesh(extent: 30, resolution: 40) {
            fill(Color(hex: 0x2C7C96))
            material(.dielectric(roughness: 0.3))
            drawMesh(surface)
        }

        fill(Color(hex: 0x0E1A24))
        material(.dielectric(roughness: 0.95))
        withState {
            translate(0, deep, 0)
            drawBox(width: 60, height: 0.2, depth: 60)
        }
    }
}
