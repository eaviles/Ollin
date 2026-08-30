import Ollin

/// Aerial perspective: the depth cue that sells scale outdoors.
///
/// Over distance the air itself takes part in the picture: short wavelengths
/// scatter out of a surface's light first, so a far ridge warms and darkens,
/// while sunlight scatters *into* the view path, veiling that same ridge in
/// blue and brightening the air toward the sun. `aerialPerspective()` computes
/// both in closed form (fog's one integral, split by wavelength), so a
/// landscape recedes into the sky the way a real one does instead of fading
/// toward one flat color. Here a file of ridgelines steps away from the
/// camera, each one a measured step paler than the last, the farthest
/// dissolving into the horizon. With a `.sky` environment the haze follows
/// the sky's own sun, rotation included: drop the sun low and the light it
/// feeds the air reddens with it. `density` is the air's optical depth per
/// world unit (leave the call bare and it derives one from the camera
/// framing); `haziness` trades the crisp molecular blue-shift for a gray
/// aerosol veil with a bright halo around the sun.
@main
final class AerialPerspective: Sketch {

    @Param(0 ... 0.03, icon: "cloud.fog", group: "Air") var density = 0.005
    @Param(0 ... 1, icon: "sun.haze", group: "Air") var haziness = 0.3
    @Param(0.06 ... 1.35, icon: "sun.max", group: "Sun") var sunHeight = 0.34
    @Param(0 ... 6.28, icon: "location.north.line", group: "Sun") var sunAround = 4.4

    private var ridges: [Mesh] = []

    override func setup() {
        // Seven ridgelines, each a long mountainous band, taller as they recede
        // so every silhouette peeks over the one in front of it.
        for i in 0 ..< 9 {
            let land = Heightfield.diamondSquare(size: 129, roughness: 0.74,
                                                 seed: UInt64(20 + i))
            let height = 4.0 + Double(i) * 2.6
            let ridge = land.mesh(width: 320, depth: 22, height: height)
                .colored(by: { p, _ in
                    let h = clamp(p.y / height, 0, 1)
                    return Color.mix(Color(hex: 0x2A2F28), Color(hex: 0x6E6B5E), h)
                })
            ridges.append(ridge)
        }
    }

    override func draw() {
        background(.black)
        toneMap(.aces)

        cameraShowcase(.sway(amplitude: 0.25, period: .tau / 0.06),
                       target: Vector3(0, 5, -70), radius: 85,
                       elevation: 0.018, fieldOfView: .pi / 3.6)

        // The sky is the backdrop and the ambient; a warm key rides the same sun
        // direction so lit faces catch it while shadow faces keep the sky's cool.
        // The aerial haze reads its sun from the environment (rotation included).
        environment(.sky(turbidity: 2.4, sunElevation: sunHeight).rotated(sunAround))
        let ce = cos(sunHeight)
        directionalLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
                         direction: Vector3(sin(sunAround) * ce, -sin(sunHeight),
                                            -cos(sunAround) * ce),
                         intensity: 1.15)
        aerialPerspective(density: density, haziness: haziness)

        fill(.white)
        for (i, ridge) in ridges.enumerated() {
            withState {
                // The first ridge sits just in front of the camera: the frame's
                // dark, nearly haze-free anchor the receding file measures against.
                translate(0, 0, 6 - Double(i) * 24)
                drawMesh(ridge)
            }
        }
    }
}
