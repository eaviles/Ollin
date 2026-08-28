import Ollin

/// A sea, made the way the ocean is measured.
///
/// Nothing here places a wave. `oceanField(_:)` writes a *spectrum* on the GPU,
/// which says how much water stands at each wavelength and heading for this
/// wind, and one inverse Fourier transform turns that whole field of
/// frequencies into the moving surface in a single step. What comes back is a
/// layer: how far each point of the water has moved sideways, how high it
/// stands, and how hard it is folding over on itself, which is where foam goes.
///
/// `drawOcean(_:)` then draws it as water with no geometry anywhere: each
/// vertex works out which corner of which cell it is from its own index and
/// reads the field for where the wave has carried it.
///
/// `waveHeight` is in world units and means what a sailor means by it, the
/// average of the tallest third, so the knob is a measurement rather than a
/// dial to turn by eye. `windSpeed` moves the energy between short chop and
/// long swell without changing that height, and `choppiness` moves water
/// toward the crests, which is what makes them narrow and the troughs wide.
@main
final class OceanSurface: Sketch {

    @Param(0.2 ... 8, icon: "water.waves") var waveHeight = 2.6
    @Param(5 ... 26, icon: "wind") var windSpeed = 12.0
    @Param(0 ... 1.6, icon: "triangle") var choppiness = 1.25
    @Param(0 ... 2.5, icon: "cloud.fog") var foam = 1.2
    @Param(icon: "sun.horizon") var lowSun = true

    override func draw() {
        background(Color(hex: 0x8FB6D4))
        toneMap(.aces)

        // The sun stands in a fixed compass direction (+Z) at this elevation,
        // and the same elevation aims the light, so the glitter on the water
        // and the sun in the sky are the same sun.
        let elevation = lowSun ? 0.13 : 0.55
        environment(.sky(turbidity: 2.6, sunElevation: elevation))
        light(.directional(Color(hex: 0xFFF1DC),
                           direction: Vector3(0, -sin(elevation), -cos(elevation)),
                           intensity: 1.1))

        // Low over the water, looking down the glitter path toward the sun.
        camera(.perspective(eye: Vector3(0, 4.6, -95), target: Vector3(0, 2.6, 220),
                            fieldOfView: .pi / 3.4))

        let sea = oceanField(Ocean(waveHeight: waveHeight,
                                   windSpeed: windSpeed,
                                   windDirection: 90,
                                   choppiness: choppiness,
                                   patchSize: 170,
                                   smallestWave: 0.6,
                                   seed: 7), resolution: 512)

        var look = WaterSurface.open
        look.foamAmount = foam
        drawOcean(sea, segments: 360, tiles: 7, water: look)
    }
}
