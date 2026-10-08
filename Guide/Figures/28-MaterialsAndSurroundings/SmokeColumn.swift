// figure: frame=0 width=680
//
// Guide figure (Chapter 28): a volume. A column of smoke rises from a stone
// pedestal under a lamp straight above it; a small ball hangs inside the
// column, veiled by the smoke in front of it, and its shadow cuts a dark
// shaft down through the smoke to the pedestal. Seeded noise built once, a
// fixed camera and lamp, no time, so the still reproduces.
import Ollin

final class SmokeColumn: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    private var plume = Volume(width: 2, height: 2, depth: 2)

    override func setup() {
        noiseSeed(12)
        plume = Volume(width: 36, height: 48, depth: 36) { u, v, w in
            let spread = 0.16 + 0.24 * v
            let fromAxis = Vector2(u - 0.5, w - 0.5).length / spread
            let floor = 0.42 + 0.35 * fromAxis * fromAxis + 0.15 * v
            let ends = min(1, v * 10) * min(1, (1 - v) * 2.5)
            return max(0, fbm(u * 3.4, w * 3.4, loop: v, radius: 0.7) - floor) * 5 * ends
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1014))
        toneMap(.aces)
        camera(.perspective(eye: Vector3(-1.2, 3.1, 7.4), target: Vector3(0, 2.6, 0),
                            fieldOfView: .pi / 4.4))
        temporalAntialiasing()
        ambientLight(Color(hex: 0x1B2230))
        castShadows()
        let lamp = Vector3(0.1, 6.6, 0.05)
        spotLight(Color(hue: 0.08, saturation: 0.3, brightness: 1), at: lamp,
                  direction: Vector3(0, -1, 0), coneAngle: 0.5, penumbra: 0.35,
                  intensity: 2.8)
        noStroke()
        fill(Color(hex: 0x3A3F47))
        drawGround(size: 20)
        withState {
            translate(0, 0.35, 0)
            fill(Color(hex: 0x6E737B))
            drawCylinder(radius: 0.55, height: 0.7)
        }
        withState {
            translate(0.1, 3.05, 0.05)
            fill(Color(hex: 0xC9A27A))
            drawSphere(radius: 0.2)
        }
        withState {
            translate(0, 2.8, 0)
            drawVolume(plume, width: 2.8, height: 4.2, depth: 2.8, medium: .smoke)
        }
    }
}
