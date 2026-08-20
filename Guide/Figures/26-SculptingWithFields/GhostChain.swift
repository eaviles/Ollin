// figure: frame=0 probe
//
// Guide figure (Chapter 26): lens flare. One lamp throws two ghosts along the
// line through the middle of the frame, each a hexagon because the iris has six
// blades, and each a different color because each surface of the lens is coated
// for a different wavelength. The second one lies over the near black slab
// rather than behind it, which is the point: a ghost is in the camera, not in
// the room. The star is turned off here, so the ghosts are what the eye lands
// on; StarPoints is the figure for the star.
import Ollin

final class GhostChain: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    private let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
    private let lamp = Vector3(-1.52, 2.80, -1.6)

    override func draw() {
        background(Color(hex: 0x080A0E))
        var camera = Camera3D(eye: Vector3(0, 1.5, 7.2), target: Vector3(0, 1.4, 0),
                              near: 0.2, far: 60,
                              projection: .perspective(fieldOfView: .pi / 3.4))
        camera.apertureBlades = 6
        self.camera(camera)

        ambientLight(Color(white: 0.05))
        directionalLight(Color(white: 0.8), direction: Vector3(-0.5, -0.8, -0.4), intensity: 0.30)
        pointLight(Color(hex: 0xFFF0D0), at: lamp, intensity: 20)
        lensFlare(LensFlare(lens: Lens.heliar.multicoated().stopped(to: 5.6), star: 0))

        // The lamp itself. A flat single-color matcap ignores the scene
        // lighting, which is what a glowing thing looks like.
        withState {
            translate(lamp)
            fill(.white)
            matcap(bulb)
            drawSphere(radius: 0.15)
        }
        matcap(nil)

        // The near slab, standing between the camera and everything else. The
        // ghosts cross it, because they are not in the room.
        fill(Color(white: 0.17))
        withState {
            translate(-1.36, 2.0, 2.6)
            drawBox(width: 0.9, height: 6.0, depth: 0.4)
        }
        // The floor and a row of blocks, to give the light something to land on.
        fill(Color(white: 0.24))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 26, height: 0.1, depth: 26)
        }
        fill(Color(hex: 0x2C4356))
        for i in 0..<6 {
            withState {
                translate(-5.0 + Double(i) * 2.0, 0.42, -4.6)
                drawBox(width: 0.66, height: 0.84, depth: 0.66)
            }
        }
    }
}
