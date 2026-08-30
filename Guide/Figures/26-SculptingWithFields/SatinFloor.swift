// figure: gif duration=8 fps=12 width=560
//
// Guide figure (Chapter 26): what a spread reflection is for. One satin floor
// between two colored walls, from a camera that never moves, switching between
// the single mirror ray and the traced lobe every two seconds. With one ray the
// floor fades to the gray environment and the room drains out of it; with the
// lobe the room is there, blurred by how rough the floor is. A GIF rather than
// two panels because the setting is read once for the whole frame, so both
// panels of a side-by-side would render with whichever value was set last.
import Ollin

final class SatinFloor: Sketch {
    override var canvasSize: CanvasSize { .square(560) }

    override func draw() {
        // Two seconds on each, so a reader can hold one against the other.
        let lobe = Int(time / 2) % 2 == 1

        background(Color(hex: 0x0A0D12))
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 9.0, azimuth: 0.35,
                         elevation: 0.26, fieldOfView: .pi / 4.4, near: 1, far: 40))
        environment(.studio.intensified(to: 1.0))
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.3), intensity: 0.8)
        rayTracedReflections()
        if lobe { glossyReflections() }

        // The satin floor: rough enough that one mirror ray cannot describe it.
        withState {
            material(.metal(roughness: 0.3))
            fill(Color(white: 0.58))
            translate(0, -0.4, 0)
            drawBox(width: 26, height: 0.8, depth: 26)
        }
        // The room the floor has to show. Both walls are matte, so they reflect
        // nothing themselves and are only here to be seen in the floor.
        withState {
            material(.matte)
            fill(Color(hex: 0xD8442A))
            translate(-4.6, 2.2, -1.0)
            drawBox(width: 0.4, height: 4.4, depth: 10)
        }
        withState {
            material(.matte)
            fill(Color(hex: 0x2F6FD8))
            translate(4.6, 2.2, -1.0)
            drawBox(width: 0.4, height: 4.4, depth: 10)
        }
        // A row from mirror to nearly matte: the ends say what the middle means.
        for (i, rough) in [0.02, 0.2, 0.4, 0.62].enumerated() {
            withState {
                material(.metal(roughness: rough))
                fill(Color(hex: 0xCFD4DC))
                translate(-2.7 + Double(i) * 1.8, 0.9, 0)
                drawSphere(radius: 0.85)
            }
        }
    }
}
