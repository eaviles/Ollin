import Ollin

/// Lights & materials — the three light kinds shading solid 3D primitives.
///
/// A solid takes the current `fill` as its surface color and is shaded by a
/// Blinn-Phong material. With no lights at all a solid still looks 3D (the auto-lit
/// default rig); here we set the lights by hand to show each kind:
///
/// - **directional** — a fixed warm key from the upper-left (parallel rays, the sun).
/// - **point** — a cyan bulb orbiting the scene, so its highlight slides across
///   the spheres.
/// - **spot** — a magenta cone sweeping left-to-right from above, lighting only
///   what falls inside it, with a soft penumbra edge.
///
/// The front row of spheres shares one fill but climbs in `shininess` left→right, so
/// the specular highlight tightens from a broad sheen to a sharp glint. Lighting is
/// per-frame (one setup shades every mesh this frame), so the lights are placed once
/// at the top of `draw()`. Small balls mark the moving lights' positions.
@main
final class Lighting3D: Sketch {

    override func draw() {
        background(Color(hex: 0x0A0B10))

        camera(.orbiting(target: Vector3(0, -0.2, 0), radius: 11,
                         azimuth: sin(time * 0.15) * 0.5, elevation: 0.35,
                         fieldOfView: .pi / 4))

        // The moving lights' positions, reused for their marker balls below.
        let pointPos = Vector3(cos(time * 0.7) * 3.5, 1.8, sin(time * 0.7) * 3.5)
        let spotPos = Vector3(sin(time * 0.5) * 3.0, 4.5, 0.5)
        let spotAim = (Vector3(sin(time * 0.5) * 1.2, -1, 0) - Vector3(0, 0, 0)).normalized

        // --- Lights (per-frame; set once, shade every mesh drawn this frame) ---
        ambientLight(Color(white: 0.12))
        directionalLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
                         direction: Vector3(-0.5, -0.8, -0.4), intensity: 0.8)
        pointLight(Color(hue: 0.5, saturation: 0.8, brightness: 1.0), at: pointPos, intensity: 1.0)
        spotLight(Color(hue: 0.85, saturation: 0.7, brightness: 1.0),
                  at: spotPos, direction: spotAim, angle: .pi / 5, penumbra: 0.5, intensity: 1.4)

        // Ground plane — matte, so it shows the spot's pool and the moving highlights.
        withState {
            translate(0, -1.3, 0)
            fill(Color(white: 0.5))
            drawPlane(width: 14, depth: 14)
        }

        // Front row: one fill, rising shininess — the highlight tightens left→right.
        let shininesses = [4.0, 16, 48, 128, 320]
        for (i, s) in shininesses.enumerated() {
            withState {
                translate(-4 + Double(i) * 2, -0.4, 1.5)
                fill(Color(hue: 0.05, saturation: 0.55, brightness: 0.9))
                specular(0.7)
                shininess(s)
                drawSphere(radius: 0.8)
            }
        }

        // Back row: a few other solids, spinning, with a softer material.
        let solids: [Mesh] = [.box(size: 1.4), .torus(radius: 0.7, tube: 0.28),
                              .icosahedron(radius: 0.95), .cylinder(radius: 0.6, height: 1.6)]
        for (i, mesh) in solids.enumerated() {
            withState {
                translate(-3.6 + Double(i) * 2.4, 0.1, -1.8)
                rotateY(time * 0.4 + Double(i))
                rotateX(0.3)
                fill(Color(hue: 0.55 + Double(i) * 0.12, saturation: 0.5, brightness: 0.9))
                specular(0.35)
                shininess(40)
                drawMesh(mesh)
            }
        }

        // Mark the moving lights with little balls in their own color. (They're shaded
        // like everything else — bright because they sit right at the source.)
        markLight(at: pointPos, color: Color(hue: 0.5, saturation: 0.8, brightness: 1.0))
        markLight(at: spotPos, color: Color(hue: 0.85, saturation: 0.7, brightness: 1.0))

        drawCaption("Lights & materials — directional + orbiting point + sweeping spot; shininess rises left→right")
    }

    private func markLight(at position: Vector3, color: Color) {
        withState {
            translate(position.x, position.y, position.z)
            fill(color)
            drawSphere(radius: 0.16)
        }
    }
}
