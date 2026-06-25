import Ollin

/// The bundled environment library, one at a time.
///
/// Ollin bundles eight CC0 HDRI environments for image-based lighting (a studio, a
/// courtyard, a forest, an interior, a city, a sunrise, a sunset, a night), all offline and
/// instant. This gallery steps through them (every few seconds, or press the left/right
/// arrows), lighting the same three physically-based balls (a polished chrome, a brushed
/// gold, and a smooth dielectric) in each, with the environment shown behind them so you can
/// see what they're reflecting. (A dozen more (`.photoStudio`, `.day`, `.dusk`, …) download
/// on demand; `Environment.allBuiltins` lists the full curated set.)
@main
final class EnvironmentGallery: Sketch {

    var offset = 0   // arrow-key stepping, added to the time-based auto-advance

    let balls: [(material: Material, fill: Color, x: Double)] = [
        (.polishedMetal,             .white,                                            -2.5),
        (.metal(roughness: 0.32),    Color(hue: 0.09, saturation: 0.45, brightness: 0.95), 0),
        (.dielectric(roughness: 0.4), Color(hue: 0.58, saturation: 0.55, brightness: 0.9),  2.5),
    ]

    override func draw() {
        let all = Environment.bundledBuiltins
        // Time-based so it's deterministic (a given frame always shows the same one);
        // the arrow keys shift `offset`. Auto-advances every 3 seconds.
        let index = ((Int(time / 3.0) + offset) % all.count + all.count) % all.count
        let entry = all[index]

        background(.black)
        toneMap(.aces)   // a filmic highlight rolloff for the HDR environments
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 7.5,
                         azimuth: sin(time * 0.15) * 0.35, elevation: 0.1,
                         fieldOfView: .pi / 4.2))

        // The current environment lights the balls and shows as the backdrop, spinning
        // slowly so the reflections drift.
        environment(entry.environment.rotated(time * 0.08))

        for ball in balls {
            withState {
                translate(ball.x, 0, 0)
                fill(ball.fill)
                material(ball.material)
                drawSphere(radius: 0.95)
            }
        }

        // The environment's name and position, as a 2D overlay over the 3D scene.
        withState {
            textFont(OutlineFont.system)
            textSize(34)
            textAlign(.center)
            noStroke()
            fill(.white)
            drawText("\(entry.name)    \(index + 1)/\(all.count)",
                     at: Vector2(Double(width) / 2, Double(height) - 80))
        }
    }

    override func keyPressed() {
        if keyCode == .leftArrow  { offset -= 1 }
        if keyCode == .rightArrow { offset += 1 }
    }
}
