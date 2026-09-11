// figure: frame=0
//
// Guide figure (Chapter 22): what the three set operations do to the same two
// solids. The pair as it stands, with the ball ghosted inside the cube, then
// their union, their intersection, and the ball cut out of the cube.
import Ollin

final class CutSolids: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let cube = Mesh.box(size: 1.3)
    let ball = Mesh.sphere(radius: 0.88, segments: 32, rings: 16)
    lazy var joined = cube.union(ball)
    lazy var shared = cube.intersection(ball)
    lazy var bitten = cube.subtracting(ball)

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.5, 8.0), target: .zero,
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        withState {
            translate(-5.1, 0.35, 0)
            pose()
            fill(Color(hex: 0x6FA8DC).withAlpha(0.45))
            material(.matte)
            drawMesh(cube)
            fill(Color(hex: 0xE8B24A))
            drawMesh(ball)
            label("a cube and a ball")
        }

        withState {
            translate(-1.7, 0.35, 0)
            pose()
            fill(Color(hex: 0xE8794A))
            material(.glossy)
            drawMesh(joined)
            label("union")
        }

        withState {
            translate(1.7, 0.35, 0)
            pose()
            fill(Color(hex: 0xB7D14A))
            material(.glossy)
            drawMesh(shared)
            label("intersection")
        }

        withState {
            translate(5.1, 0.35, 0)
            pose()
            fill(Color(hex: 0x4AC7A0))
            material(.glossy)
            drawMesh(bitten)
            label("cube minus ball")
        }
    }

    /// Turned so a face, an edge, and the bite are all in view at once.
    private func pose() {
        rotateY(0.62)
        rotateX(0.3)
    }

    private func label(_ text: String) {
        withBillboard(at: Vector3(0, -1.4, 0)) {
            noStroke()
            fill(.white)
            textSize(21)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
