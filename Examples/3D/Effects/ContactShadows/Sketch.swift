import Ollin

/// Contact shadows: the fine dark seam that seats an object on a surface.
///
/// A shadow map covers the broad shadow, but its finite resolution and its
/// acne bias leave the last sliver of contact open, so a resting object can
/// read as hovering a hair above the floor. `contactShadows()` closes that
/// seam: a short screen-space ray marches from each pixel toward the casting
/// light through the scene's own depth, darkening exactly where geometry
/// meets geometry. The soft shadow here is deliberately wide, so the map
/// alone leaves every base loose; flip the toggle and watch the shapes settle
/// onto the floor. The floating sphere is the control: no contact, so the
/// seam never appears under it. The length dial is in world units (0 derives
/// a short reach from the scene scale).
@main
final class ContactShadows: Sketch {

    @Param(icon: "circle.bottomhalf.filled", group: "Contact")
    var contact = true

    @Param(0...40, icon: "ruler", group: "Contact")
    var length = 0.0

    @Param(0...1, icon: "shadow", group: "Shadow")
    var softness = 0.7

    override func draw() {
        background(Color(white: 0.09))

        cameraShowcase(.autoOrbit(period: 40), target: Vector3(0, 0.9, 0),
                       radius: 9, elevation: 0.30, fieldOfView: .pi / 3.6)

        ambientLight(Color(white: 0.22))
        directionalLight(.white, direction: Vector3(-0.55, -0.85, -0.35), intensity: 0.95)
        castShadows()
        shadowSoftness(softness)
        if contact { contactShadows(length: length > 0 ? length : nil) }

        // A loose still life, every base flush with the floor: the seam the
        // contact march restores runs along each one.
        withState {
            fill(Color(hex: 0xC05A3E))
            translate(-1.9, 0.7, -0.4)
            drawBox(width: 1.4, height: 1.4, depth: 1.4)
        }
        withState {
            fill(Color(hex: 0x4E8FB0))
            translate(0.4, 0.62, 1.3)
            drawSphere(radius: 0.62)
        }
        withState {
            fill(Color(hex: 0xE0B040))
            translate(1.8, 0.55, -1.0)
            drawCylinder(radius: 0.55, height: 1.1)
        }
        withState {
            fill(Color(hex: 0x7A9A6D))
            translate(0.2, 0.28, -1.8)
            rotate(.pi / 2, axis: .unitX)
            drawTorus(radius: 0.62, tube: 0.26)
        }
        // The control: this one really does hover, so no seam should form.
        withState {
            fill(Color(white: 0.8))
            translate(-0.6, 2.6, 0.6)
            drawSphere(radius: 0.4)
        }

        withState {
            fill(Color(white: 0.42))
            translate(0, -0.06, 0)
            drawBox(width: 14, height: 0.12, depth: 14)
        }

        drawCaption("contactShadows \(contact ? "on" : "off")"
                    + (contact && length > 0 ? String(format: ", length %.0f", length) : ""))
    }
}
