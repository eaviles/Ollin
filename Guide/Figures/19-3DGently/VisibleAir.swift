// figure: frame=0 width=680
//
// Guide figure (Chapter 19): air you can see. A window-gobo spot marched as a
// beam through thin haze over a dark set: the panes read as tilted bars of
// bright air before they land as a window on the floor, and the standing props
// carve their own dark shafts out of the beam (castShadows). A faint cool rim
// beam crosses behind. Fixed camera, no time, so the still reproduces.
import Ollin

final class VisibleAir: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    // The window cookie, drawn once: white panes behind black mullions.
    let window: LightCookie = {
        var frame = Image(width: 128, height: 128, color: .black)
        for y in 0..<128 {
            for x in 0..<128 {
                let inFrame = x > 10 && x < 117 && y > 10 && y < 117
                let onMullion = abs(x - 64) < 6 || abs(y - 64) < 6
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    override func draw() {
        background(Color(hex: 0x04050A))
        ambientLight(Color(white: 0.015))
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 10.5,
                         azimuth: 0.12, elevation: 0.15, fieldOfView: .pi / 4.2))

        // The key: warm, high on the left, throwing the window through the air.
        spotLight(Color(hue: 0.10, saturation: 0.28, brightness: 1.0),
                  at: Vector3(-4.6, 6.0, 2.6), direction: Vector3(0.62, -0.74, -0.28),
                  angle: .pi / 8, penumbra: 0.22, intensity: 3.2,
                  cookie: window, roll: 0.18)
        // The rim: cool and faint, crossing the set laterally behind the props.
        spotLight(Color(hue: 0.58, saturation: 0.45, brightness: 1.0),
                  at: Vector3(5.6, 2.6, -4.8), direction: Vector3(-0.92, -0.18, 0.36),
                  angle: .pi / 10, penumbra: 0.5, intensity: 0.7)

        castShadows()
        volumetricLight(0.9, anisotropy: 0.45)
        fog(Color(hex: 0x0A0E18), density: 0.02)

        fill(Color(hex: 0x2E3138))
        withState {
            translate(0, -0.55, 0)
            drawBox(width: 22, height: 1.1, depth: 22)
        }
        fill(Color(hex: 0x8A8478))
        withState {
            translate(-0.4, 1.35, -0.3)
            drawCylinder(radius: 0.42, height: 2.7)
        }
        fill(Color(hex: 0x707A86))
        withState {
            translate(1.7, 0.62, 1.3)
            drawSphere(radius: 0.62)
        }
        fill(Color(hex: 0x66605A))
        withState {
            translate(-2.1, 0.85, 1.8)
            rotateY(0.5)
            drawBox(width: 0.75, height: 1.7, depth: 0.75)
        }
        fill(Color(hex: 0x5A6472))
        withState {
            translate(2.6, 1.05, -1.9)
            drawCone(radius: 0.55, height: 2.1)
        }
    }
}
