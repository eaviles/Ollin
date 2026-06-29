import Ollin

/// Physically-based materials: a metallic × roughness sweep.
///
/// `Material.physicallyBased` shades a mesh with an energy-conserving Cook-Torrance
/// microfacet model: the surface *color* is the current `fill`, and two numbers set the
/// rest. **Roughness** runs left to right (a tight, mirror-like highlight smearing into a
/// broad, soft one), and **metalness** runs top to bottom: the bottom row is a dielectric
/// (a colored diffuse body with a neutral highlight), the top row a metal (no diffuse, so
/// the highlight is tinted by the surface color, the way gold and copper are). The middle row
/// is the unphysical in-between, there to read the transition.
///
/// Lit by direct lights alone here, a smooth metal is mostly dark with a few bright moving
/// hotspots; that's physically what a metal with nothing to reflect does. Set an
/// `environment(_:)` and those darks fill in with reflections of the surroundings
/// (image-based lighting), which is what makes metals read as metal.
@main
final class PhysicalMaterials: Sketch {

    let columns = 6        // roughness 0 … 1
    let rows = 3           // metalness 1 (metal) … 0 (dielectric)
    let spacing = 2.3

    // One albedo per metalness row: a warm gold for the metal (so the tinted reflection
    // reads), a neutral half, and a saturated blue dielectric.
    let albedos = [
        Color(hue: 0.11, saturation: 0.65, brightness: 0.95),   // gold-ish metal
        Color(white: 0.72),                                     // neutral
        Color(hue: 0.58, saturation: 0.70, brightness: 0.90),   // blue dielectric
    ]

    override func draw() {
        background(Color(hex: 0x0B0C12))

        // A gentle sway: the highlights slide because the point light below orbits, so
        // the camera barely needs to move; this keeps the chart centered and its labels
        // on-canvas. The radius/FOV leave a margin past the outer spheres for the labels.
        cameraShowcase(.sway(amplitude: 0.22, period: .tau / 0.1), target: .zero, radius: 19,
                    elevation: 0.26, fieldOfView: .pi / 4)

        // A warm key plus a cool fill, and a point light orbiting with us to keep the
        // hotspots moving across every sphere.
        let lightPos = Vector3(cos(time * 0.5) * 9, 7, sin(time * 0.5) * 9)
        ambientLight(Color(white: 0.10))
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.4, -0.7, -0.5), intensity: 1.1)
        directionalLight(Color(kelvin: 8000), direction: Vector3(0.6, 0.2, 0.4), intensity: 0.35)
        pointLight(.white, at: lightPos, intensity: 1.4)

        for row in 0..<rows {
            let metallic = 1.0 - Double(row) / Double(rows - 1)   // 1 … 0
            for col in 0..<columns {
                let roughness = mapRoughness(col)
                let pos = gridPosition(col: col, row: row)
                withState {
                    translate(pos.x, pos.y, pos.z)
                    fill(albedos[row])
                    material(Material(shading: .physicallyBased,
                                      metallic: metallic, roughness: roughness))
                    drawSphere(radius: 0.9)
                }
            }
        }

        drawAxisLabels()
    }

    // Roughness sweep, kept just off 0 so the smoothest sphere still shows a finite
    // highlight rather than a single aliased pixel.
    private func mapRoughness(_ col: Int) -> Double {
        map(Double(col), 0, Double(columns - 1), 0.05, 1.0)
    }

    private func gridPosition(col: Int, row: Int) -> Vector3 {
        let x = (Double(col) - Double(columns - 1) / 2) * spacing
        let y = (Double(rows - 1) / 2 - Double(row)) * spacing
        return Vector3(x, y, 0)
    }

    // Labels ride under the spheres (projected from world space) so they stay readable
    // and on-canvas as the chart sways: each row's metalness under its leftmost sphere,
    // and a roughness caption centered under the bottom row.
    private func drawAxisLabels() {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.85))

            let names = ["metal", "mixed", "dielectric"]
            for row in 0..<rows {
                let first = gridPosition(col: 0, row: row)
                if let p = project(first + Vector3(0, -1.4, 0)) {
                    drawText(names[row], at: p)
                }
            }

            // Centered under the bottom row (x = 0, the grid's axis of symmetry).
            let bottomY = gridPosition(col: 0, row: rows - 1).y
            if let p = project(Vector3(0, bottomY - 1.4, 0)) {
                drawText("rougher →", at: p)
            }
        }
    }
}
