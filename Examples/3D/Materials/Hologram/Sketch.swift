import Ollin

/// The hologram finish: a diffraction grating ruled into a metal, the rainbow
/// of a hologram sticker or the back of a disc. Fine parallel grooves send each
/// color of a light off at its own angle, so the color at a point follows the
/// angle between the light and the eye and walks through the spectrum as
/// either moves. `Material.hologram` turns it on; `gratingSpacing` is the
/// distance between the grooves in **nanometers**, light's own scale, and
/// `gratingRotation` turns them in the surface.
///
/// Three bodies share the finish under one light that circles. The **plate**
/// shows the grating equation plainly: the rainbow is a band whose colors sit
/// where their wavelength says, and it slides across the plate as the light
/// moves. The **sphere** puts the first order on both sides of the highlight,
/// with the fainter second and third orders beyond. The **sheet** carries a
/// crumpled normal map, so every facet turns the grooves its own way and the
/// rainbow breaks into pieces: holographic foil in 3D. The map is authored in
/// `setup()` from a `FacetField`, the same sheet of facets the 2D foil filter
/// reads, and `crinkle` is its strength.
@main
final class Hologram: Sketch {
    @Param("Grating spacing", 600 ... 2000, icon: "line.3.horizontal") var spacing = 1000.0
    @Param("Roughness", 0.05 ... 0.8, icon: "circle.lefthalf.filled") var roughness = 0.3
    @Param("Crinkle", 0 ... 2, icon: "scribble") var crinkle = 1.0
    @Param("Light speed", 0 ... 1, icon: "sun.max") var lightSpeed = 0.25

    private var crumple: Image?

    override func setup() {
        // A sheet of flat facets as a green-up normal map: each texel holds the
        // normal of the facet under it, so the grooves turn per facet.
        let size = 512
        let field = FacetField.crumpled(in: Rectangle(x: 0, y: 0, width: Double(size), height: Double(size)),
                                        spacing: 64, crinkle: 0.8, seed: 7)
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let n = field.facet(containing: p)?.normal ?? Vector3(0, 0, 1)
                let i = (y * size + x) * 4
                bytes[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        crumple = Image(width: size, height: size, premultipliedRGBA: bytes)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        cameraShowcase(.sway(amplitude: 0.14, period: .tau / 0.07), target: Vector3(0, 0.1, 0),
                       radius: 12.2, elevation: 0.14, fieldOfView: .pi / 4.6)
        // A dim room so the metal between the orders reads as metal; the
        // rainbow itself answers the circling key light alone.
        environment(.studio.intensified(to: 0.35).lightingOnly())
        toneMap(.aces, exposure: 1.0)
        // The key swings across the front of the three bodies, so the plate's
        // band slides across it and comes back; at the start it sits mid-plate.
        let a = time * lightSpeed * .tau
        directionalLight(.white,
                         direction: Vector3(-(0.35 + 0.5 * sin(a)), -0.45, -(0.55 + 0.35 * cos(a))),
                         intensity: 1.3)

        var finish = Material.hologram
        finish.gratingSpacing = spacing
        finish.roughness = roughness
        fill(Color(white: 0.82))

        // Left: the flat plate.
        withState {
            translate(-2.75, 0.1, 0)
            rotateX(.pi / 2)
            material(finish)
            drawPlane(width: 2.3, depth: 2.3)
        }
        // Middle: the sphere.
        withState {
            translate(0, 0.1, 0)
            material(finish)
            drawSphere(radius: 1.1)
        }
        // Right: the crumpled sheet, the grooves turned by every facet.
        if let crumple {
            withState {
                translate(2.75, 0.1, 0)
                rotateX(.pi / 2)
                material(finish)
                drawMesh(Mesh.plane(width: 2.3, depth: 2.3).normalMapped(crumple, scale: crinkle))
            }
        }
        // A plain metal floor, so the three read as objects in a room.
        withState {
            translate(0, -1.35, 0)
            fill(Color(white: 0.45))
            material(.metal(roughness: 0.5))
            drawPlane(width: 11, depth: 6)
        }

        drawCaption("a grating in the metal: the rainbow sits where the angle says")
    }
}
