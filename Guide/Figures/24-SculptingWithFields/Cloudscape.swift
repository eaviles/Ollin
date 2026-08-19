// figure: frame=0 width=680
//
// Guide figure (Chapter 24): a raymarched cloudscape baked into the procedural
// sky. A chrome ball and a matte plain under a scattered deck: the same weather
// in the backdrop, the lighting, and the reflection, from one bake. Fixed sun
// and phase, no time, so the still reproduces.
import Ollin

final class Cloudscape: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(.black)
        toneMap(.aces)
        camera(.orbiting(target: Vector3(0, 1.6, 0), radius: 9,
                         azimuth: 0.5, elevation: 0.12, fieldOfView: .pi / 3.1))
        environment(.sky(turbidity: 2.4, sunElevation: 0.5).rotated(0.7)
            .clouds(Clouds(coverage: 0.5, phase: 2)))
        fill(.white)
        material(.polishedMetal)
        drawSphere(radius: 1.3)
        material(.matte)
        fill(Color(white: 0.55))
        withState { translate(0, -1.7, 0); drawBox(width: 40, height: 0.4, depth: 40) }
    }
}
