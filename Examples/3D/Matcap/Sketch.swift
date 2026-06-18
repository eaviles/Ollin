import Ollin

/// Matcaps — a whole look in one sphere texture.
///
/// A *matcap* (material capture) bakes a surface and its lighting into a single image,
/// sampled by the view-space normal. `matcap(_:)` shades a mesh straight from it, with
/// no scene lights and at almost no cost — reach for chrome, clay, wax, or a cel look
/// by name. Here the same sphere wears a built-in in each cell of a grid the camera
/// orbits; because a matcap is keyed to the *view*, the shading slides as it turns.
///
/// The built-ins are real baked studio captures (CC0, from the Blender community). The
/// last cell is a `Matcap.shaded(…)` generated on the CPU — the "roll your own" path,
/// no asset — and you can just as well pass any matcap PNG via `loadImage`.
@main
final class MatcapGallery: Sketch {

    // A built-in matcap per cell, plus one generated to show the escape hatch. All are
    // drawn over fill(.white) so they read as-is (a non-white fill would recolor them).
    let entries: [(name: String, matcap: Matcap)] = [
        ("chrome",     .chrome),
        ("bronze",     .bronze),
        ("carpaint",   .carpaint),
        ("hardSurfaceGrey", .hardSurfaceGrey),
        ("clay",       .clay),
        ("terracotta", .terracotta),
        ("sage",       .sage),
        ("clayWarm",   .clayWarm),
        ("pearl",      .pearl),
        ("ceramic",    .ceramic),
        ("ceramicDark", .ceramicDark),
        ("wax",        .wax),
        ("resin",      .resin),
        ("studio",     .studio),
        ("toon",       .toon),
        ("toonDark",   .toonDark),
        ("checkNormal", .checkNormal),
        ("shaded()",   .shaded(baseColor: Color(hex: 0x4FC3F7), metallic: true, roughness: 0.15)),
    ]

    let columns = 6
    let spacing = 2.4

    override func draw() {
        background(Color(hex: 0x0B0C12))

        // Orbit so the view-keyed matcap shading shifts as the spheres turn.
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 21,
                         azimuth: sin(time * 0.15) * 0.5, elevation: 0.18,
                         fieldOfView: .pi / 4.5))

        fill(.white)   // show each matcap as captured (fill tints it)
        let rows = (entries.count + columns - 1) / columns
        for (i, entry) in entries.enumerated() {
            let pos = gridPosition(col: i % columns, row: i / columns, rows: rows)
            withState {
                translate(pos.x, pos.y, pos.z)
                matcap(entry.matcap)
                drawSphere(radius: 0.95)
            }
            drawLabel(entry.name, under: pos)
        }
    }

    private func gridPosition(col: Int, row: Int, rows: Int) -> Vector3 {
        let x = (Double(col) - Double(columns - 1) / 2) * spacing
        let y = (Double(rows - 1) / 2 - Double(row)) * spacing
        return Vector3(x, y, 0)
    }

    // Place a name under each sphere by projecting its world position to the canvas, so
    // the labels ride the orbit. Labels are plain 2D, drawn after (and over) the meshes.
    private func drawLabel(_ name: String, under worldPos: Vector3) {
        guard let p = project(worldPos + Vector3(0, -1.2, 0)) else { return }
        withState {
            textFont(OutlineFont.system)
            textSize(24)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.85))
            drawText(name, at: p)
        }
    }
}
