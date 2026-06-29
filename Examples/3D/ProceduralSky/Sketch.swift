import Ollin

/// A procedural sky: image-based lighting with no asset.
///
/// `environment(.sky(...))` synthesizes a physically-based daylight dome at runtime (no HDRI
/// to load or download) and lights the scene with it, exactly like a loaded environment:
/// the metals gather their reflections from the sky, the matte floor catches its bounce, and
/// the sky itself draws as the backdrop. Here the sun travels a full loop across the sky,
/// circling the compass while it rises and dips, so the whole sky (and everything reflecting
/// it) turns with it: warm and hazy when low, cool and clear overhead.
///
/// `turbidity` is the atmospheric haze, `sunElevation` the sun's height above the horizon in
/// radians, and `groundAlbedo` how much light bounces up from below. `rotated(_:)` spins the
/// sun around the compass; because rotation is a sample-direction tweak, not a re-bake,
/// circling the sun is free, and only its changing elevation refreshes the lighting.
@main
final class ProceduralSky: Sketch {

    let columns = 5

    override func draw() {
        // The sun travels a full loop: `rotated` swings it all the way around the compass while
        // its elevation eases between low and high, so it rises, arcs over, and circles back.
        let cycle = time * 0.6
        let elevation = (sin(cycle) * 0.5 + 0.5) * (.pi / 2 - 0.1) + 0.05
        let azimuth = cycle
        let turbidity = map(elevation, 0.05, .pi / 2, 5.0, 2.0)

        background(.black)
        toneMap(.aces)   // a filmic rolloff for the sky's bright highlights and the sun

        cameraShowcase(.sway(amplitude: 0.5, period: .tau / 0.08), target: Vector3(0, 0.55, 0), radius: 12,
                    elevation: 0.10, fieldOfView: .pi / 4.2)

        // The sky is the only light. It both lights the materials and draws as the backdrop.
        environment(.sky(turbidity: turbidity, sunElevation: elevation).rotated(azimuth))

        // A row of metals sweeping mirror -> rough, resting on the floor, so the moving sky
        // reads in the reflections.
        for col in 0..<columns {
            let x = (Double(col) - Double(columns - 1) / 2) * 2.1
            let roughness = map(Double(col), 0, Double(columns - 1), 0.03, 0.9)
            withState {
                translate(x, 0.55, 0)
                fill(.white)
                material(.metal(roughness: roughness))
                drawSphere(radius: 0.85)
            }
        }

        // A wide matte floor: large enough to recede to the horizon, so the ground meets the
        // sky in one clean line and catches its downward bounce.
        withState {
            translate(0, -0.5, 0)
            fill(Color(white: 0.55))
            material(.roughPlastic)
            drawBox(width: 400, height: 0.4, depth: 400)
        }
    }
}
