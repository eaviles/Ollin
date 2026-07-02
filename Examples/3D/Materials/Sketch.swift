import Ollin

/// The material library: one surface, eighteen finishes.
///
/// A `Material` sets how a mesh responds to light; the surface *color* stays the
/// current `fill`. The same sphere wears each built-in here, laid out in a grid the
/// camera orbits so the view-angle finishes come alive: the iridescent rainbows shift,
/// the velvet rim slides around the silhouette, the jade and wax glow through their
/// edges. A point light orbits with the camera so every highlight keeps moving.
///
/// The grid runs:
///
/// - **dielectric finishes** — `matte`, `clay`, `rubber`, `plastic` (top row),
///   `ceramic`, `glossy`, `polished`, then the stylized models begin.
/// - **iridescent family** — `iridescent`, `soapBubble`, `oilSlick`, `beetle`.
/// - **sparkle family** — `glitter` (fine flake dust) and `sequin` (chunky facets),
///   flashing as the orbit sweeps.
/// - **rim / subsurface** — `velvet`, `jade`, `wax`.
/// - **non-photorealistic** — `toon` (cel) and `gooch` (warm→cool).
///
/// Each is a plain value, so you'd build your own the same way (or copy and tweak a
/// built-in — `var m = Material.glossy; m.iridescence = 0.4`).
@main
final class Materials3D: Sketch {

    // The material, the fill it's shown over, and a label. Fills are picked so each
    // finish reads: a neutral/dark body under the iridescent ones (so the rainbow
    // shows), a tinted body where the material implies one (jade green, wax cream).
    let entries: [(name: String, material: Material, fill: Color)] = [
        ("matte",      .matte,      Color(hue: 0.00, saturation: 0.55, brightness: 0.85)),
        ("clay",       .clay,       Color(hue: 0.05, saturation: 0.55, brightness: 0.70)),
        ("rubber",     .rubber,     Color(white: 0.22)),
        ("plastic",    .plastic,    Color(hue: 0.58, saturation: 0.70, brightness: 0.90)),
        ("ceramic",    .ceramic,    Color(white: 0.92)),
        ("glossy",     .glossy,     Color(hue: 0.98, saturation: 0.70, brightness: 0.85)),
        ("polished",   .polished,   Color(white: 0.78)),
        ("iridescent", .iridescent, Color(white: 0.18)),
        ("soapBubble", .soapBubble, Color(white: 0.80)),
        ("oilSlick",   .oilSlick,   Color(white: 0.08)),
        ("beetle",     .beetle,     Color(hue: 0.40, saturation: 0.65, brightness: 0.25)),
        ("glitter",    .glitter,    Color(hue: 0.66, saturation: 0.75, brightness: 0.30)),
        ("sequin",     .sequin,     Color(hue: 0.93, saturation: 0.80, brightness: 0.55)),
        ("velvet",     .velvet,     Color(hue: 0.93, saturation: 0.65, brightness: 0.40)),
        ("jade",       .jade,       Color(hue: 0.42, saturation: 0.55, brightness: 0.55)),
        ("wax",        .wax,        Color(hue: 0.10, saturation: 0.30, brightness: 0.90)),
        ("toon",       .toon,       Color(hue: 0.07, saturation: 0.80, brightness: 0.95)),
        ("gooch",      .gooch,      Color(white: 0.55)),
    ]

    let columns = 4
    let spacing = 2.4

    override func draw() {
        background(Color(hex: 0x0B0C12))

        // Orbit the grid slowly so the view-angle finishes (iridescence, rim, jade)
        // shift and shimmer rather than sitting frozen.
        cameraShowcase(.sway(amplitude: 0.6, period: .tau / 0.12), target: .zero, radius: 12.5,
                    elevation: 0.32, fieldOfView: .pi / 4.5)

        // A point light orbiting with us keeps the highlights sliding; a warm key and a
        // soft ambient fill out the modeling.
        let lightPos = Vector3(cos(time * 0.6) * 6, 5, sin(time * 0.6) * 6)
        ambientLight(Color(white: 0.14))
        directionalLight(Color(kelvin: 5600), direction: Vector3(-0.4, -0.7, -0.5), intensity: 0.7)
        pointLight(.white, at: lightPos, intensity: 1.0)

        let rows = (entries.count + columns - 1) / columns
        for (i, entry) in entries.enumerated() {
            let col = i % columns
            let row = i / columns
            let pos = gridPosition(col: col, row: row, rows: rows)
            withState {
                translate(pos.x, pos.y, pos.z)
                fill(entry.fill)
                material(entry.material)
                drawSphere(radius: 0.85)
            }
            drawLabel(entry.name, under: pos)
        }
    }

    private func gridPosition(col: Int, row: Int, rows: Int) -> Vector3 {
        let x = (Double(col) - Double(columns - 1) / 2) * spacing
        let y = (Double(rows - 1) / 2 - Double(row)) * spacing
        return Vector3(x, y, 0)
    }

    // Place a name under each sphere by projecting its world position to the canvas —
    // so the labels ride the orbit with the spheres.
    private func drawLabel(_ name: String, under worldPos: Vector3) {
        guard let p = project(worldPos + Vector3(0, -1.15, 0)) else { return }
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.85))
            drawText(name, at: p)
        }
    }
}
