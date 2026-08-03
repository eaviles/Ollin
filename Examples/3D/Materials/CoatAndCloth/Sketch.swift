import Ollin

/// Clearcoat and sheen: the two layered finishes on the physically-based material.
///
/// **Clearcoat** (top row) is a thin polished lacquer over the base: the body keeps its
/// own roughness while the coat carries a second, glassy reflection, which is how car
/// paint and piano lacquer read. Compare the first two spheres: the same red metal with
/// and without the coat. The base also dims slightly under a coat, by exactly the light
/// the film reflects away. Layer `sparkle` on top for the metallic-flake version.
///
/// **Sheen** (bottom row) is fabric fuzz: stray fibers catch light at grazing angles, so
/// the silhouette glows softly in `sheenColor` while the body stays matte, and the body
/// dims to keep the energy honest. Again the first two spheres are the same blue with
/// and without it. A sheen tinted away from the `fill` gives the two-tone velvet look
/// (the last sphere: a deep red body rimmed in orange).
///
/// Both lobes ride `Material.physicallyBased`, shade under plain lights, and pick up
/// reflections from an `environment(_:)` the way the rest of the physically-based tier
/// does. The presets used here: `.carPaint(roughness:)`, `.lacquer`, `.satin`, `.felt`.
@main
final class CoatAndCloth: Sketch {

    let spacing = 2.4

    override func draw() {
        background(Color(hex: 0x0B0C12))

        cameraShowcase(.sway(amplitude: 0.22, period: .tau / 0.1), target: .zero, radius: 15,
                       elevation: 0.22, fieldOfView: .pi / 4)
        environment(.studio.intensity(1.05).backgroundBlur(0.55))

        // A warm key sweeping with time so the coat's hotspot and the sheen's rim both
        // travel; the environment supplies the reflections and the fill light.
        let lightPos = Vector3(cos(time * 0.5) * 8, 6, sin(time * 0.5) * 8)
        pointLight(Color(kelvin: 5200), at: lightPos, intensity: 1.2)

        let paintRed = Color(hue: 0.99, saturation: 0.82, brightness: 0.72)
        let clothBlue = Color(hue: 0.62, saturation: 0.65, brightness: 0.45)

        // Top row: the coat story. The same red metal bare and coated, then the two
        // dielectric coat looks (piano black, metallic flake).
        row(y: spacing / 2, labels: ["car paint", "no coat", "lacquer", "flake"]) { col in
            switch col {
            case 0:
                fill(paintRed)
                material(.carPaint(roughness: 0.45))
            case 1:
                fill(paintRed)
                material(.metal(roughness: 0.45))
            case 2:
                fill(Color(white: 0.05))
                material(.lacquer)
            default:
                var m = Material.carPaint(roughness: 0.5)
                m.sparkle = 0.85
                m.sparkleColor = Color(hue: 0.1, saturation: 0.4, brightness: 1.0)
                fill(Color(hue: 0.6, saturation: 0.7, brightness: 0.55))
                material(m)
            }
        }

        // Bottom row: the sheen story. The same blue cloth bare and fuzzed, then the
        // tighter satin band and the two-tone velvet.
        row(y: -spacing / 2, labels: ["felt", "no sheen", "satin", "velvet"]) { col in
            switch col {
            case 0:
                fill(clothBlue)
                material(.felt)
            case 1:
                fill(clothBlue)
                material(.dielectric(roughness: 0.9))
            case 2:
                fill(Color(hue: 0.09, saturation: 0.25, brightness: 0.85))
                material(.satin)
            default:
                var m = Material.felt
                m.sheenColor = Color(hue: 0.07, saturation: 0.9, brightness: 0.95)
                fill(Color(hue: 0.99, saturation: 0.9, brightness: 0.3))
                material(m)
            }
        }

        drawCaption("clearcoat & sheen: layered finishes on the physically-based material")
    }

    /// One row of four spheres with a projected label under each.
    private func row(y: Double, labels: [String], configure: (Int) -> Void) {
        for col in 0..<4 {
            let x = (Double(col) - 1.5) * spacing
            withState {
                translate(x, y, 0)
                configure(col)
                drawSphere(radius: 0.92)
            }
            withState {
                textFont(OutlineFont.system)
                textSize(24)
                textAlign(.center)
                noStroke()
                fill(Color(white: 0.8))
                if let p = project(Vector3(x, y - 1.35, 0)) {
                    drawText(labels[col], at: p)
                }
            }
        }
    }
}
