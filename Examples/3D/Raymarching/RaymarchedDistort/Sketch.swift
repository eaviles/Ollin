import Ollin
import Foundation

// The sculpting distortions of the raymarched combinators: `twisted` screws a form around
// its axis, `bent` curls it along its run, `displaced` ripples the surface with a sine
// field, and `roughened` carves it with signed value noise (the rock look). Four plinths,
// one distortion each, the amounts breathing so the surfaces work. Each is a distance
// bound, and the march compensates, so even the strong moments stay solid.
@main
final class RaymarchedDistort: Sketch {
    override func draw() {
        raymarchResolution(0.5)   // four fields on screen at once
        background(Color(hex: 0x12141a))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.35), target: Vector3(0, 0.2, 0), radius: 9.5,
                    elevation: 0.3, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.15, softness: 0.3)
        ambientLight(Color(white: 0.17))
        material(.jade)

        // A twisted column: the square cross-section screws around y, the rate swinging.
        let twistRate = sin(t * 0.9) * 1.6
        drawSDF3D(SDF3D.box(width: 0.85, height: 2.6, depth: 0.85)
            .twisted(twistRate)
            .at(x: -3.2, y: 0.3, z: 0)
            .colored(Color(hex: 0x46c2ff)))

        // A bent bar: a straight slab curling about z as the rate swings.
        let bendRate = 0.25 + sin(t * 0.7) * 0.55
        drawSDF3D(SDF3D.box(width: 2.6, height: 0.5, depth: 0.7)
            .bent(bendRate)
            .at(x: -1.05, y: 0.3, z: 0)
            .colored(Color(hex: 0xffb454)))

        // A rippled sphere: sine-product displacement, the swell breathing.
        let swell = 0.05 + (sin(t * 1.3) * 0.5 + 0.5) * 0.1
        drawSDF3D(SDF3D.sphere(radius: 0.95)
            .displaced(amplitude: swell, frequency: 6.5)
            .at(x: 1.15, y: 0.15, z: 0)
            .colored(Color(hex: 0xff6f61)))

        // A roughened sphere: signed value noise turns the ball to rock.
        drawSDF3D(SDF3D.sphere(radius: 0.95)
            .roughened(amplitude: 0.16, frequency: 3.2)
            .rotatedY(t * 0.4)
            .at(x: 3.3, y: 0.15, z: 0)
            .colored(Color(hex: 0x9aa7b8)))

        // A shared plinth row grounds the four forms.
        material(.matte)
        fill(Color(hex: 0x39415a))
        translate(0, -1.15, 0)
        drawBox(width: 8.6, height: 0.5, depth: 1.9)
    }
}
