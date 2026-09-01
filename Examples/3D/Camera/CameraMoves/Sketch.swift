import Ollin

/// Cinematic camera moves: pick a shot instead of keyframing the camera.
///
/// One still life (a glossy sphere, a turning box, a torus) on a floor, viewed
/// through Ollin's curated `CameraMove`s in turn: a `.turntable` spin, a `.sway`,
/// a `.pushIn` / `.pullOut` dolly, a `.tilt`, the `.orbitAndRise` beauty pass, a
/// `.reveal`, and a `.handheld` drift. Each is one call, `cameraMove(_:)`, that
/// composes over the pose the last one left, so the shots chain smoothly. Click or
/// press any key to step through them by hand.
///
/// Every move is a way to look at an object on a turntable: it modulates the orbit
/// pose (azimuth, elevation, radius) around the centered target, which suits the
/// kind of scene Ollin draws rather than flying through a space.
@main
final class CameraMoves3D: Sketch {

    private let moves: [(name: String, move: CameraMove)] = [
        ("turntable",     .turntable(period: 14)),
        ("sway",          .sway(amplitude: .pi / 5, period: 7)),
        ("pushIn",        .pushIn(by: 0.55, in: 2.5)),
        ("pullOut",       .pullOut(by: 1.0 / 0.55, in: 2.5)),   // back to the framed radius
        ("tilt up",       .tilt(to: 0.95, in: 2.5)),
        ("tilt level",    .tilt(to: 0.3, in: 2.5)),
        ("orbitAndRise",  .orbitAndRise(period: 14, rise: 0.5, in: 5)),
        ("reveal",        .reveal(in: 3.5)),
        ("handheld",      .handheld(amount: 0.05, speed: 0.8)),
    ]

    private var index = 0
    private var lastStep = 0.0
    private let holdSeconds = 5.0

    override func mousePressed() { step() }
    override func keyPressed() { step() }

    private func step() {
        index = (index + 1) % moves.count
        lastStep = time
    }

    override func draw() {
        background(Color(white: 0.045))

        // Auto-advance unless the viewer is stepping by hand.
        if time - lastStep > holdSeconds { step() }

        let current = moves[index]
        cameraMove(current.move, target: Vector3(0, -0.2, 0), radius: 8,
                   elevation: 0.32, fieldOfView: .pi / 4)

        lightingPreset(.threePoint)
        castShadows()

        // The ground that catches the shadows.
        withState {
            translate(0, -1.4, 0)
            fill(Color(white: 0.5)); specular(0.05)
            drawPlane(width: 16, depth: 16)
        }

        withState {
            translate(-2.3, -0.4, 0.4)
            fill(Color(white: 0.85)); specular(0.7); specularSharpness(120)
            drawSphere(radius: 1.0)
        }
        withState {
            translate(0.4, -0.2, -0.3)
            rotateY(time * 0.35); rotateX(0.3)
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9)); specular(0.4); specularSharpness(48)
            drawBox(size: 1.5)
        }
        withState {
            translate(2.6, -0.5, 0.6)
            rotateX(0.9); rotateY(time * 0.5)
            fill(Color(hue: 0.58, saturation: 0.45, brightness: 0.9)); specular(0.5); specularSharpness(64)
            drawTorus(radius: 0.75, tube: 0.3)
        }

        drawCaption("Camera move: \(current.name)   ·   click or press a key to step")
    }
}
