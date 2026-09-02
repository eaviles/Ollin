// figure: frame=0
//
// Guide figure (Chapter 22): dispersion. Two solid glass balls in front of three
// thin white bars on a dark wall, one bar behind each ball as the camera sees it,
// with `sceneThroughGlass()` on so the bars show inside them on any Mac. The left ball is clear glass and shows the bars turned
// over in plain gray. The right ball adds `dispersion`, so each color bends its
// own way and the bars' lens images differ in size between red and blue: a red
// edge outside each bar (only the widest picture reaches it) and a yellow one
// inside (red and green reach, blue has not yet).
import Ollin

final class Prism: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.studio.intensified(to: 1.1))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.5)
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 6.6, azimuth: 0,
                         elevation: 0.02, fieldOfView: .pi / 4.6, near: 1, far: 30))
        sceneThroughGlass()

        // A dark wall and three thin white bars painted onto it (flush, so the
        // picture the balls read has no step in its depth), each outer bar where
        // the line from the camera through a ball's center meets the wall.
        withState {
            material(.dielectric(roughness: 0.8))
            fill(Color(hex: 0x23262E))
            translate(0, 0, -3.6)
            drawBox(width: 16, height: 10, depth: 0.4)
        }
        for x in [-2.7, 0.0, 2.7] {
            withState {
                material(.dielectric(roughness: 0.8))
                fill(.white)
                translate(x, 0, -3.36)
                drawBox(width: 0.7, height: 10, depth: 0.1)
            }
        }

        // The same ball twice: clear on the left, a prism on the right.
        for (x, dispersion) in [(-1.75, 0.0), (1.75, 1.0)] {
            withState {
                fill(.white)
                material(.glass(ior: 1.8, thickness: 2.4, dispersion: dispersion))
                translate(x, 0, 0.4)
                drawSphere(radius: 1.2)
            }
        }
        drawCaption("dispersion: 0 (left) and 1 (right)")
    }
}
