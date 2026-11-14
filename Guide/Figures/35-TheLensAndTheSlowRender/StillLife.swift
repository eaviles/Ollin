// figure: frame=0 traced=512 denoise
//
// Guide figure (Chapter 35): the chapter's finished sketch, a still life of
// stylized finishes through a lens. The directive renders it the way the
// chapter's export command does, `--path-traced 512 --denoise`, so the image
// is the traced frame: the toon ball keeps its band, the chrome ball mirrors
// it, and the lamps along the back open into six-sided discs.
import Ollin

final class StillLife: Sketch {
    override func draw() {
        background(Color(hex: 0x0B0A0D))

        // The camera and its lens: an opening, a focus, and six blades.
        var lens = Camera3D(eye: Vector3(0, 1.3, 5.6), target: Vector3(0, 0.5, 0),
                            projection: .perspective(fieldOfView: .pi / 4.8))
        lens.aperture = 0.11
        lens.focusDistance = 5.5
        lens.apertureBlades = 6
        camera(lens)
        depthOfField()      // the lens in the window; a traced export has its own

        // One softbox from the upper left, and a dim studio for the chrome.
        environment(.studio.intensified(to: 0.18))
        rectangleLight(Color(hex: 0xFFF1DC), at: Vector3(-3.0, 3.4, 2.6),
                       direction: Vector3(0.6, -0.68, -0.42),
                       width: 2.4, height: 1.6, intensity: 11)
        castShadows()

        // The table.
        withState {
            material(.dielectric(roughness: 0.35))
            fill(Color(hex: 0x3A2A22))
            translate(0, -0.25, -3)
            drawBox(width: 14, height: 0.5, depth: 16)
        }

        // In focus: a toon ball, and a chrome ball that mirrors it.
        withState {
            material(.toon)
            fill(Color(hex: 0xE8762C))
            translate(-0.55, 0.5, 0.1)
            drawSphere(radius: 0.5, segments: 64, rings: 32)
        }
        withState {
            material(.metal(roughness: 0.03))
            fill(Color(white: 0.95))
            translate(0.75, 0.42, 0.25)
            drawSphere(radius: 0.42, segments: 64, rings: 32)
        }

        // Nearer than the focus: a jade ring lying on the table.
        withState {
            material(.jade)
            fill(Color(hex: 0x3FA06A))
            translate(0.35, 0.13, 1.7)
            drawTorus(radius: 0.4, tube: 0.13, segments: 96, sides: 32)
        }

        // Past the focus: velvet on the left, glitter on the right.
        withState {
            material(.velvet)
            fill(Color(hex: 0x6A2C8C))
            translate(-1.6, 0.62, -1.9)
            drawSphere(radius: 0.62, segments: 64, rings: 32)
        }
        withState {
            var flakes = Material.glitter
            flakes.sparkleColor = Color(hue: 0.12, saturation: 0.75, brightness: 1)
            material(flakes)
            fill(Color(hue: 0.98, saturation: 0.8, brightness: 0.45))
            translate(1.75, 0.58, -2.0)
            drawSphere(radius: 0.58, segments: 64, rings: 32)
        }

        // A string of small lamps, far behind and far out of focus. Each is a
        // mesh that gives off light, so the traced frame counts it as a lamp.
        var lamp = Mesh.sphere(radius: 0.045)
        lamp.material = MeshMaterial(emissiveColor: Color(red: 10, green: 6, blue: 2.6))
        for i in 0 ..< 11 {
            withState {
                translate(-4.0 + Double(i) * 0.8, 2.3 + 0.25 * sin(Double(i) * 1.3), -9.5)
                drawMesh(lamp)
            }
        }
    }
}
