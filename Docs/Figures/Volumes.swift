// figure: frame=0
//
// Figure for Docs/3D/Volumes.md: three volumes in one scene, each a seeded
// ball of noise in its own medium. On the left, smoke scattering a spot
// light, a ball hanging inside it veiled by the smoke in front and casting
// its shadow down through it. In the middle, fire glowing from inside, a dark
// ring passing through the glow. On the right, ink in front of a pale wall,
// taking light away and giving none back.
import Ollin

final class Volumes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    private let puff: Volume = {
        let noise = Volume.noise(width: 40, height: 40, depth: 40, frequency: 3.5, octaves: 4, seed: 6)
        return Volume(width: 40, height: 40, depth: 40) { u, v, w in
            let r = Vector3(u, v, w).distance(to: Vector3(0.5, 0.5, 0.5)) * 2
            return max(0, 1.3 * noise.value(u: u, v: v, w: w) - 1.25 * r * r - 0.12) * 3
        }
    }()

    override func draw() {
        background(Color(hex: 0x111317))
        toneMap(.aces)
        camera(.perspective(eye: Vector3(0, 1.5, 9.2), target: Vector3(0, 1.25, 0), fieldOfView: .pi / 5.2))
        ambientLight(Color(hex: 0x1D2430))
        castShadows()
        spotLight(Color(hex: 0xFFE4C4), at: Vector3(-2.8, 5.8, 0.6), direction: Vector3(-0.05, -1, -0.12),
                  coneAngle: 0.9, penumbra: 0.5, intensity: 2.6)
        directionalLight(Color(white: 0.9), direction: Vector3(-0.2, -0.5, -1), intensity: 1.1,
                         castsShadow: false)
        noStroke()

        fill(Color(hex: 0x2E3238))
        drawGround(size: 30)
        // The pale wall behind the ink.
        fill(Color(hex: 0xEDE7DA))
        withState { translate(3.1, 1.9, -1.8); drawBox(width: 3.6, height: 3.8, depth: 0.1) }

        // Smoke, lit, with a ball inside it.
        fill(Color(hex: 0xC9A27A))
        withState { translate(-2.8, 1.55, 0.2); drawSphere(radius: 0.2) }
        withState {
            translate(-2.9, 1.25, 0)
            drawVolume(puff, size: 2.3, medium: Medium(density: 2.4, color: Color(white: 0.85), anisotropy: 0.3))
        }

        // Fire, with a dark ring through it.
        fill(Color(hex: 0x1C1C20))
        withState { translate(0, 1.25, 0); rotateX(1.2); drawTorus(radius: 0.8, tube: 0.09, segments: 64, sides: 16) }
        withState {
            translate(0, 1.25, 0)
            drawVolume(puff, size: 2.3, medium: .fire)
        }

        // Ink, in front of the wall.
        withState {
            translate(2.75, 1.45, 0)
            drawVolume(puff, size: 2.3, medium: Medium(density: 3, color: .black))
        }
    }
}
