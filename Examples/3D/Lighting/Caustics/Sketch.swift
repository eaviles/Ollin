import Ollin

/// Caustics: the light a glass or a polished metal focuses onto what's around it.
///
/// A shadow says where light *can't* reach; a caustic says where a lens or a
/// mirror *concentrated* it instead. `caustics()` traces photons from the light
/// through every transmissive and mirror-polished surface and draws where they
/// land, so a clear sphere throws the classic bright spot into its own shadow, a
/// tinted sphere throws a colored one, and a chrome ring folds light into the
/// curved fan a wedding band leaves on a table:
///
/// ```swift
/// directionalLight(.white, direction: Vector3(-0.3, -1, -0.2))
/// caustics()
/// material(.glass(thickness: 1.8))
/// drawSphere(radius: 0.9)
/// ```
///
/// The pattern's sharpness comes from how each light path focused, not from a
/// blur pass, so the hot spot under a sphere stays a point while the ring's fan
/// stays a fine curve. `dispersion:` splits refracted paths by wavelength for
/// prism rainbows; `causticsQuality(_:)` trades photons for frame rate. Needs a
/// ray-tracing GPU (Apple silicon), a camera, and a light. **Hold the space bar**
/// to switch the caustics off and compare: the shadows go back to plain darkness.
@main
final class Caustics: Sketch {

    override func draw() {
        background(Color(hex: 0x101318))
        cameraShowcase(.sway(amplitude: 0.2, period: .tau / 0.08),
                       target: Vector3(0, 0.6, 0), radius: 10.5, elevation: 0.42,
                       fieldOfView: .pi / 4, near: 1, far: 40)
        environment(.studio.intensity(0.55).backgroundBlur(0.6))
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 2.2)
        castShadows()
        rayTracedReflections()   // the glass shows the actual scene through itself
        if !isKeyDown(" ") { caustics() }

        // A matte floor: the screen the light patterns land on.
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(hex: 0x878c99))
            translate(0, -0.5, 0)
            drawBox(width: 26, height: 1.0, depth: 16)
        }

        // A clear solid sphere: a lens, hovering at the height that puts its focal
        // point right on the floor (a ball lens focuses about half a radius past
        // its surface), so the bright spot lands tight inside its own shadow,
        // where direct light can't be.
        withState {
            material(.glass(thickness: 2.4))
            fill(.white)
            translate(-2.4, 1.7, 0)
            drawSphere(radius: 1.2)
        }

        // A tinted absorbing sphere: the same lens in bottle green, so the spot
        // it throws is colored by the glass it crossed.
        withState {
            material(.glass(thickness: 2.0,
                            attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.6))
            fill(.white)
            translate(2.5, 1.15, -0.4)
            drawSphere(radius: 1.0)
        }

        // A chrome ring lying almost flat: its inner wall folds the light into
        // the curved fan a ring leaves beside itself on a sunlit table.
        withState {
            material(.metal(roughness: 0.06))
            fill(Color(hex: 0xf2f4f8))
            translate(0.3, 0.42, 2.6)
            rotateX(.pi / 2 * 0.92)
            drawTorus(radius: 1.15, tube: 0.16)
        }

        drawCaption(isKeyDown(" ")
            ? "Caustics off (release space to focus the light again)"
            : "Caustics on (hold space to compare)")
    }
}
