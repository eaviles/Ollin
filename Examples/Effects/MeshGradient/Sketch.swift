import Ollin

/// The mesh-gradient generator: soft blobs of color drifting on independent
/// orbits, blended by inverse-distance weighting over a domain-warped field:
/// the animated-wallpaper look, one `generate` call.
///
/// `distortion` smears the field organically, `swirl` winds a vortex around
/// the center, and `grain` dithers the color boundaries while overlaying film
/// grain. The gradient flows because `phase` is fed `time`; hold it fixed for
/// a still composition.
@main
final class MeshGradient_Example: Sketch {
    @Param(0...1) var distortion = 0.8
    @Param(0...1) var swirl = 0.1
    @Param(0...1) var mixing = 0.5
    @Param(0...1) var grain = 0.15
    @Param(0...0.5) var drift = 0.25   // how fast the blobs roam

    override func draw() {
        let gradient = generate(.meshGradient(
            colors: [Color(hex: 0xE0EAFF), Color(hex: 0x241D9A),
                     Color(hex: 0xF75092), Color(hex: 0x9F50D3)],
            distortion: distortion, swirl: swirl, mixing: mixing, grain: grain,
            phase: time * drift * 4))
        drawImage(gradient.image, 0, 0)
    }
}
