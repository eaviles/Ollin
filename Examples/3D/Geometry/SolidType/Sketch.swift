import Ollin

/// Solid type: a word set in an outline font and extruded into a 3D solid.
///
/// `Mesh.text(...)` builds the whole word as one mesh, standing upright and
/// centered on the model origin, so it takes a material, catches the light, and
/// throws a shadow like any other solid. `Mesh.textGlyphs(...)` returns the same
/// word a letter at a time, each still in its place, which is what letters
/// moving on their own need: `mesh.center` is where that letter sits, so a
/// letter turns about itself rather than about the word.
///
/// Two things the calls take care of. Text is laid out with y growing down the
/// canvas and a 3D world counts y up, so a plain extrusion of a glyph arrives
/// upside down. And a glyph's curves are simplified against the size they are
/// asked for, so a letter one world unit tall would come back as a lump: the
/// outline is traced large and scaled down instead.
///
/// `size` is the em in world units (a capital stands about 0.7 of it), not
/// `textSize`, which is measured in canvas points.
///
/// The one-call form is `drawText3D(word, size: 2, depth: 0.4)`, which builds the
/// solid fresh every frame. This sketch keeps its own meshes instead, so the
/// thickness knob decides when they are rebuilt.
///
/// Self-contained: the system face, no bundled asset.
@main
final class SolidType: Sketch {

    @Param(0.05...1.2, icon: "cube") var depth = 0.35
    @Param(0...1.5, icon: "waveform") var nod = 0.7
    @Param(icon: "arrow.trianglehead.2.clockwise") var turning = true

    private let word = "Ollin"
    private let size = 2.0

    /// Built once, rebuilt only when the thickness knob moves: every call
    /// triangulates the glyphs and raises their walls again.
    private var solid = Mesh(positions: [], indices: [])
    private var letters: [Mesh] = []
    private var builtDepth = -1.0

    override func setup() {
        build()
    }

    private func build() {
        solid = .text(word, size: size, depth: depth)
        letters = Mesh.textGlyphs(word, size: size, depth: depth)
        builtDepth = depth
    }

    override func draw() {
        if depth != builtDepth { build() }

        background(Color(hex: 0x0A0B12))
        cameraShowcase(.sway(amplitude: 0.4, period: .tau / 0.11),
                       target: Vector3(0, 1.7, 0), radius: 12, elevation: 0.16,
                       fieldOfView: .pi / 4, near: 0.5, far: 60)

        directionalLight(.white, direction: Vector3(-0.5, -0.8, -0.45), intensity: 1.4)
        pointLight(Color(hex: 0xFFD9A8), at: Vector3(5, 3.5, 5), intensity: 0.7,
                   castsShadow: false)
        ambientLight(Color(hex: 0x151A2A))
        castShadows()
        noStroke()

        // The floor the letters stand on, so their shadows say how thick they are.
        withState {
            fill(Color(hex: 0x14161F))
            material(.dielectric(roughness: 0.7))
            drawPlane(width: 26, depth: 26)
        }

        // The whole word as one solid, turning on its axis.
        let standing = solid.bounds.max.y
        withState {
            translate(0, standing * 3 + 0.9, 0)
            if turning { rotateY(sin(time * 0.5) * 0.6) }
            fill(Color(hex: 0xE8C88A))
            material(.metal(roughness: 0.28))
            drawMesh(solid)
        }

        // The same word a letter at a time, each nodding about its own center.
        withState {
            // Lifted clear of the floor, since a letter nodding about its own
            // center would otherwise dip through it.
            translate(0, standing + 0.55, 0)
            fill(Color(hex: 0x7FD4FF))
            material(.dielectric(roughness: 0.35))
            for (i, letter) in letters.enumerated() {
                let pivot = letter.center
                withState {
                    translate(pivot)
                    rotateX(sin(time * 1.4 + Double(i) * 0.7) * nod)
                    translate(-pivot)
                    drawMesh(letter)
                }
            }
        }

        drawCaption("Solid type: one word as a mesh, and the same word a letter at a time")
    }
}
