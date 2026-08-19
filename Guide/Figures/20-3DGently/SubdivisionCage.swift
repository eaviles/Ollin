// figure: frame=0
//
// Guide figure (Chapter 20): a low-poly cage refined into a smooth solid.
// The same extruded star three times: the control cage as a wireframe, one
// level of subdivision, and two levels with the cage ghosted around the
// smooth form it produced.
import Ollin

final class SubdivisionCage: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let cage = Mesh.extrude(Profile.star(points: 5, outerRadius: 1.05, innerRadius: 0.5),
                            depth: 0.75)
    lazy var once = cage.subdivided(levels: 1)
    lazy var smooth = cage.subdivided(levels: 2)

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.35, 7.4), target: .zero,
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        withState {
            translate(-2.5, 0.25, 0)
            pose()
            stroke(Color(hex: 0x9FD8D2))
            strokeWeight(1.2)
            wireframe()
            drawMesh(cage)
            label("the cage")
        }

        withState {
            translate(0, 0.25, 0)
            pose()
            fill(Color(hex: 0xE8B24A))
            material(.matte)
            drawMesh(once)
            label("levels: 1")
        }

        withState {
            translate(2.5, 0.25, 0)
            pose()
            fill(Color(hex: 0xE8794A))
            material(.glossy)
            drawMesh(smooth)
            wireframe()
            stroke(Color(hex: 0x9FD8D2).withAlpha(0.3))
            strokeWeight(1)
            drawMesh(cage)
            label("levels: 2")
        }
    }

    /// Face the stars toward the camera, tipped just enough to read as solid.
    private func pose() {
        rotateY(0.55)
        rotateX(0.28)
    }

    private func label(_ text: String) {
        withBillboard(at: Vector3(0, -1.55, 0)) {
            noStroke()
            fill(.white)
            textSize(23)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
