// figure: gif duration=8 fps=12 width=560
//
// Guide figure (Chapter 26): how far a reflection is allowed to travel. One
// corridor of two facing mirrors, from a camera that never moves, stepping the
// reflection chain from the default pair of surfaces up to five. At the pair
// the far panel is filled with sky, because that is where the chain stops.
// Every step after that opens one more door.
import Ollin

final class MirrorCorridor: Sketch {
    override var canvasSize: CanvasSize { .square(560) }

    /// Two seconds on each count, so a reader can see one door open at a time.
    let counts = [2, 3, 4, 5]

    override func draw() {
        let step = counts[min(Int(time / 2), counts.count - 1)]

        background(Color(hex: 0x0A0D12))
        // The eye stands between the two mirrors and looks at one of them at an
        // angle, so a reflected ray crosses the corridor and meets the other
        // mirror. It holds still: the tunnel is the only thing that changes.
        camera(.orbiting(target: Vector3(3, 0, 0), radius: 3.2, azimuth: -1.216,
                         elevation: 0.12, fieldOfView: .pi / 3, near: 0.2, far: 40))
        environment(.night)
        directionalLight(.white, direction: Vector3(0.3, 1, 0.4), intensity: 2.2)
        rayTracedReflections()
        reflectionBounces(step)

        for side in [-1.0, 1.0] {
            withState {
                material(.metal(roughness: 0.04))
                fill(Color(hex: 0xEBEDF2))
                translate(side * 3.2, 0, 0)
                drawBox(width: 0.4, height: 6, depth: 14)
            }
        }
        withState {
            material(.dielectric(roughness: 0.35))
            fill(Color(hex: 0xE4572E))
            translate(0.9, -0.7, 0.2)
            drawBox(width: 0.8, height: 0.8, depth: 0.8)
        }

        // The environment behind the mirrors is bright, so the label carries its own
        // dark strip rather than fighting whatever happens to be behind it.
        let label = step == 2 ? "reflectionBounces(2), the default" : "reflectionBounces(\(step))"
        noStroke()
        textSize(24)
        textAlign(.left, .top)
        fill(Color(white: 0, alpha: 0.5))
        drawRect(14, 14, textWidth(label) + 22, 40)
        fill(Color(white: 1, alpha: 0.95))
        drawText(label, 25, 22)
    }
}
