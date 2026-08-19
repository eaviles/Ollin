// figure: gif duration=6 fps=15 width=560
//
// Guide figure (Chapter 20): the shape of a light's throw. Two shaped lights
// over one small set: a downlight wearing an IES profile (a hot center with a
// spill ring, authored inline) pooling its signature on the left, and a spot
// projecting a window-frame cookie whose slow roll rocks the panes of light
// across the floor on the right.
import Ollin

final class ShapedLight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    // A small authored IES file: candela by angle off the beam, nothing else.
    // The dip at 15-20 degrees and the second rise at 30 make the ring.
    let ringFile = """
    IESNA:LM-63-2002
    TILT=NONE
    1 1000 1 8 1 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 5 10 15 20 30 40 90
    0
    1000 950 700 250 150 520 120 0
    """
    lazy var ring = IESProfile(string: ringFile)!

    // The window cookie, drawn once: white panes behind black mullions.
    let window: LightCookie = {
        var frame = Image(width: 128, height: 128, color: .black)
        for y in 0..<128 {
            for x in 0..<128 {
                let inFrame = x > 8 && x < 119 && y > 8 && y < 119
                let onMullion = abs(x - 64) < 5 || abs(y - 64) < 5
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(0, 4.4, 9.4), target: Vector3(0, 0.4, 0),
                            fieldOfView: .pi / 4.2))
        ambientLight(Color(white: 0.05))

        // The profiled downlight: the file above shapes the throw; the light
        // itself is an ordinary point light aimed straight down.
        pointLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
                   at: Vector3(-2.6, 2.4, 0.4), intensity: 1.4, profile: ring)

        // The gobo: a spot projecting the window image, rocking on its roll.
        let rock = sin(loopProgress(over: 6) * .tau) * 0.16
        spotLight(Color(hue: 0.12, saturation: 0.25, brightness: 1.0),
                  at: Vector3(3.6, 4.6, 4.2), direction: Vector3(-0.32, -0.66, -0.55),
                  angle: 0.85, penumbra: 0.12, intensity: 1.25,
                  cookie: window, roll: rock)

        fill(Color(hex: 0x8A94A6))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(Mesh.plane(width: 15, depth: 10)) }
        withState {
            translate(0, 1.6, -3.6)
            fill(Color(hex: 0x6E7789))
            material(.matte)
            drawBox(width: 15, height: 3.6, depth: 0.2)
        }

        // Something under each light: a sphere in the downlight's pool, a low
        // slab the window panes climb over.
        withState {
            translate(-2.6, 0.55, 0.4)
            fill(Color(hex: 0xE2643C))
            material(.plastic)
            drawSphere(radius: 0.55)
        }
        withState {
            translate(1.6, 0.28, 0.2)
            rotateY(0.3)
            fill(Color(hex: 0x2C8C86))
            material(.plastic)
            drawBox(width: 1.5, height: 0.55, depth: 1.5)
        }
    }
}
