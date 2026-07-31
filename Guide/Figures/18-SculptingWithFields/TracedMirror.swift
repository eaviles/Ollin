// figure: frame=0
//
// Guide diagram (Chapter 18): what a traced reflection shows that a
// screen-space one cannot. Three solids on a nearly polished floor. The
// box's reflection shows its underside, the face turned toward the floor,
// which the camera has no view of and so has no pixels of to borrow.
import Ollin

final class TracedMirror: Sketch {
    override var canvasSize: CanvasSize { .square(640) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.studio)
        rayTracedReflections()
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7.4, azimuth: 0.6,
                         elevation: 0.14, fieldOfView: .pi / 4.6, near: 2, far: 22))

        // The mirror: a broad, nearly polished floor.
        withState {
            material(.metal(roughness: 0.12))
            fill(Color(white: 0.55))
            translate(0, -0.05, 0)
            drawBox(width: 14, height: 0.1, depth: 14)
        }

        // Two solids in frame.
        withState {
            material(.dielectric(roughness: 0.3))
            fill(Color(hex: 0xE4572E))
            translate(-1.1, 0.75, 0.2)
            drawSphere(radius: 0.75)
        }
        withState {
            material(.metal(roughness: 0.25))
            fill(Color(hex: 0xF2CC8F))
            translate(1.2, 0.6, -0.6)
            drawBox(width: 1.2, height: 1.2, depth: 1.2)
        }

        // A third solid overhead, cropped by the frame, giving the floor
        // something to reflect that the camera only partly sees.
        withState {
            material(.dielectric(roughness: 0.25))
            fill(Color(hex: 0x5AA9E6))
            translate(0.35, 2.9, 1.9)
            drawSphere(radius: 0.85)
        }
    }
}
