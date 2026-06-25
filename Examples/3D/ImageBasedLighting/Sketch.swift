import Ollin

/// Image-based lighting: metals that reflect their surroundings.
///
/// `environment(_:)` lights the scene with an HDRI, so physically-based materials gather
/// their ambient and reflections from it. This is what makes a metal read as metal: the
/// near-black smooth metal from the direct-light-only chart fills in with a reflection of
/// the world around it.
///
/// The top row is metal sweeping roughness left to right (a mirror smearing into a soft
/// satin); the bottom row is a colored dielectric doing the same. The environment alone
/// lights them, no other lights set, and the camera orbits so the reflections move.
@main
final class ImageBasedLighting: Sketch {

    let columns = 6
    let spacing = 2.2

    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)   // a filmic highlight rolloff for the HDR environment

        camera(.orbiting(target: Vector3(0, 0, 0), radius: 16,
                         azimuth: sin(time * 0.12) * 0.5, elevation: 0.16,
                         fieldOfView: .pi / 4.2))

        // The environment is the only light. Spin it slowly so the key light and the
        // reflections drift across the spheres.
        environment(.sunset.rotated(time * 0.15))

        for col in 0..<columns {
            let roughness = map(Double(col), 0, Double(columns - 1), 0.02, 1.0)
            // Top: metal (its reflection tinted by fill). Bottom: blue dielectric.
            withState {
                translate(xFor(col), 1.3, 0)
                fill(Color(hue: 0.09, saturation: 0.35, brightness: 0.95))
                material(.metal(roughness: roughness))
                drawSphere(radius: 0.85)
            }
            withState {
                translate(xFor(col), -1.3, 0)
                fill(Color(hue: 0.58, saturation: 0.65, brightness: 0.9))
                material(.dielectric(roughness: roughness))
                drawSphere(radius: 0.85)
            }
        }
    }

    private func xFor(_ col: Int) -> Double {
        (Double(col) - Double(columns - 1) / 2) * spacing
    }
}
