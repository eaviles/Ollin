import Ollin

/// Lighting presets: one call relights the whole scene.
///
/// The same arrangement of solids on a floor, cycled through Ollin's curated
/// `LightingPreset`s every few seconds: `.standard`, `.threePoint`, `.goldenHour`,
/// `.noir`, `.studio`, and `.moonlight`. Each is an ambient plus a set of lights
/// tuned with color temperatures (`Color(kelvin:)`), so switching mood is a single
/// `lightingPreset(_:)` instead of hand-placing lights.
///
/// The last entry is built right here in the sketch (a tweaked copy of `.noir`
/// plus a hot point light) to show the presets are an open value type you can
/// extend, not a fixed menu. Press any key to step through them by hand; the mouse
/// stays free for the camera (drag to orbit, scroll to dolly).
@main
final class LightingPresets3D: Sketch {

    // The built-ins, plus a custom rig (copy a preset, mutate it, add a light).
    private let presets: [(name: String, preset: LightingPreset)] = {
        var custom = LightingPreset.noir
        custom.ambient = Color(white: 0.05)
        custom.lights.append(.point(Color(kelvin: 8000), at: Vector3(2.5, 2.5, 2.5), intensity: 1.4))
        return [
            ("standard", .standard),
            ("threePoint", .threePoint),
            ("goldenHour", .goldenHour),
            ("noir", .noir),
            ("studio", .studio),
            ("moonlight", .moonlight),
            ("custom (noir + cyan bulb)", custom),
        ]
    }()

    private var index = 0
    private var lastStep = 0.0
    private let holdSeconds = 3.5

    override func keyPressed() { step() }

    private func step() {
        index = (index + 1) % presets.count
        lastStep = time
    }

    override func draw() {
        background(Color(white: 0.04))

        // Auto-advance unless the viewer is stepping by hand.
        if time - lastStep > holdSeconds { step() }

        cameraShowcase(.sway(amplitude: 0.45, period: .tau / 0.12), target: Vector3(0, -0.1, 0), radius: 9,
                    elevation: 0.32, fieldOfView: .pi / 4)

        let current = presets[index]
        lightingPreset(current.preset)
        castShadows()

        // The ground that catches the shadows: matte, neutral.
        withState {
            translate(0, -1.4, 0)
            fill(Color(white: 0.55))
            specular(0.05)
            drawPlane(width: 16, depth: 16)
        }

        // A small still life: a glossy sphere, a spinning box, a torus.
        withState {
            translate(-2.3, -0.4, 0.4)
            fill(Color(white: 0.85)); specular(0.7); shininess(120)
            drawSphere(radius: 1.0)
        }
        withState {
            translate(0.4, -0.2, -0.3)
            rotateY(time * 0.35); rotateX(0.3)
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9)); specular(0.4); shininess(48)
            drawBox(size: 1.5)
        }
        withState {
            translate(2.6, -0.5, 0.6)
            rotateX(0.9); rotateY(time * 0.5)
            fill(Color(hue: 0.58, saturation: 0.45, brightness: 0.9)); specular(0.5); shininess(64)
            drawTorus(radius: 0.75, tube: 0.3)
        }

        drawCaption("Lighting presets: \(current.name)   ·   press a key to step")
    }
}
