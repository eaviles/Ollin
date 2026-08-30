// figure: frame=0 probe
//
// Guide figure (Chapter 26): the star on a source. Six blades on the iris throw
// six arms, because the pattern is the far-field diffraction of the opening
// itself. The arms fan into color at their tips, since a longer wavelength
// bends further, and the core blows out the way a bright source does.
import Ollin

final class StarPoints: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    private let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
    private let lamp = Vector3(-0.5, 2.3, -2.0)

    override func draw() {
        background(Color(hex: 0x070910))
        var camera = Camera3D(eye: Vector3(0, 1.6, 6.6), target: Vector3(0, 1.7, 0),
                              near: 0.2, far: 60,
                              projection: .perspective(fieldOfView: .pi / 3.4))
        camera.apertureBlades = 6
        self.camera(camera)

        ambientLight(Color(white: 0.04))
        pointLight(Color(hex: 0xFFEFCC), at: lamp, intensity: 16)
        // The ghosts are held back so the star is what the eye lands on. Both
        // come from the same opening: turn the blades to 0 and the arms go with
        // the hexagons.
        lensFlare(LensFlare(lens: Lens.heliar.stopped(to: 5.6), amount: 0.35,
                            star: 1.3, starSize: 0.42))

        withState {
            translate(lamp)
            fill(.white)
            matcap(bulb)
            drawSphere(radius: 0.13)
        }
        matcap(nil)

        fill(Color(white: 0.26))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 26, height: 0.1, depth: 26)
        }
        fill(Color(hex: 0x2A3F52))
        for i in 0..<7 {
            withState {
                translate(-5.4 + Double(i) * 1.8, 0.34, -4.2)
                drawBox(width: 0.56, height: 0.68, depth: 0.56)
            }
        }
    }
}
