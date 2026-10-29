// figure: frame=0 width=680
//
// Guide figure (Chapter 29): the bounce. Two identical puffs of white cloud
// side by side over a dark floor, a low sun behind and above them, the left
// one lit once (`bounce: 0`), the right one with the light the medium passes
// on to itself (`bounce: 1`). Seeded noise built once, a fixed camera and
// light, no time, so the still reproduces.
import Ollin

final class BouncedCloud: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    private let puff: Volume = {
        let noise = Volume.noise(width: 48, height: 40, depth: 48, frequency: 3.2, octaves: 4, seed: 21)
        return Volume(width: 48, height: 40, depth: 48) { u, v, w in
            let c = Vector3(u - 0.5, (v - 0.45) * 1.25, w - 0.5)
            let r = c.length * 2
            return max(0, 1.35 * noise.value(u: u, v: v, w: w) - 1.1 * r * r - 0.18) * 3.5
        }
    }()

    override func draw() {
        background(Color(hex: 0x0D1016))
        toneMap(.aces)
        camera(.perspective(eye: Vector3(0, 1.7, 8.6), target: Vector3(0, 1.25, 0),
                            fieldOfView: .pi / 5))
        temporalAntialiasing()
        ambientLight(Color(hex: 0x141A24))
        castShadows()
        // The sun behind and above the clouds, shining toward the camera.
        directionalLight(Color(hex: 0xFFEBD2), direction: Vector3(0.25, -0.55, 1), intensity: 2.2)
        noStroke()
        fill(Color(hex: 0x262A31))
        drawGround(size: 24)
        for (index, bounce) in [0.0, 1.0].enumerated() {
            withState {
                translate(Double(index) * 3.6 - 1.8, 1.45, 0)
                drawVolume(puff, width: 3.2, height: 2.6, depth: 3.2,
                           medium: Medium(density: 4, color: Color(white: 0.95),
                                          anisotropy: 0.5, bounce: bounce))
            }
        }
        withOverlay {
            textFont(.system)
            for (index, label) in ["bounce: 0", "bounce: 1"].enumerated() {
                drawText(label, width * (0.25 + 0.5 * Double(index)), height - 34, size: 20,
                         color: Color(white: 0.75), align: .center, .top)
            }
        }
    }
}
