// figure: gif duration=6 fps=1 width=480
//
// Guide figure (Chapter 21): the lighting presets. The same still life,
// relit once per second by a single call: standard, threePoint, goldenHour,
// noir, studio, moonlight.
import Ollin

final class PresetTour: Sketch {
    let presets: [(name: String, preset: LightingPreset)] = [
        ("standard", .standard),
        ("threePoint", .threePoint),
        ("goldenHour", .goldenHour),
        ("noir", .noir),
        ("studio", .studio),
        ("moonlight", .moonlight),
    ]

    override func draw() {
        background(Color(white: 0.04))
        camera(.orbiting(target: Vector3(0, 0.35, 0), radius: 11,
                         azimuth: 0.3, elevation: 0.3, fieldOfView: .pi / 4.2))

        let current = presets[Int(time) % presets.count]
        lightingPreset(current.preset)
        castShadows()

        fill(Color(white: 0.55)); specular(0.05)
        drawPlane(width: 20, depth: 20)

        withState {
            translate(-2.2, 1.0, 0.4)
            fill(Color(white: 0.85)); specular(0.7); specularSharpness(120)
            drawSphere(radius: 1.0)
        }
        withState {
            translate(0.4, 0.75, -0.5); rotateY(0.5); rotateX(0.2)
            fill(Color(hue: 0.04, saturation: 0.5, brightness: 0.9))
            specular(0.4); specularSharpness(48)
            drawBox(size: 1.5)
        }
        withState {
            translate(2.6, 0.62, 0.7); rotateX(0.9); rotateY(0.6)
            fill(Color(hue: 0.58, saturation: 0.45, brightness: 0.9))
            specular(0.5); specularSharpness(64)
            drawTorus(radius: 0.75, tube: 0.3)
        }

        drawCaption("lightingPreset(.\(current.name))")
    }
}
