import Ollin

/// The four ways two solids combine, side by side: a cube and a ball that pokes
/// out of every one of its faces.
///
/// `union` keeps everything either solid covers, so the cube grows six domes.
/// `intersection` keeps only what both cover, which is the cube with its corners
/// and edges rounded off. `subtracting` takes the ball out of the cube, leaving a
/// hollow with a round floor, and taking the cube out of the ball instead leaves
/// the six caps joined at the middle. Every one of them is a real `Mesh`: the
/// same thing a generator hands you, ready to draw, to break, or to write out for
/// a printer.
///
/// The cuts happen once, in `setup()`. Cutting one solid with another is CPU
/// geometry rather than a draw call, so the piece to keep is the mesh, not the
/// call that made it.
@main
final class CutAndJoin: Sketch {
    override var loopDuration: Double? { 16 }

    private var pieces: [(name: String, mesh: Mesh)] = []

    override func setup() {
        let cube = Mesh.box(size: 1.25)
        let ball = Mesh.sphere(radius: 0.85, segments: 32, rings: 16)
        pieces = [
            ("union",        cube.union(ball)),
            ("intersection", cube.intersection(ball)),
            ("cube - ball",  cube.subtracting(ball)),
            ("ball - cube",  ball.subtracting(cube)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x0A0B10))
        cameraShowcase(.sway(amplitude: 0.12, period: 16), target: .zero, radius: 12,
                       elevation: 0.14, fieldOfView: .pi / 3.6)

        let spacing = 2.5
        let x0 = -spacing * Double(pieces.count - 1) / 2
        for (i, piece) in pieces.enumerated() {
            withState {
                translate(x0 + spacing * Double(i), -0.5, 0)
                withState {
                    // One turn a lap, so the loop closes on the frame it opened.
                    rotateY(time * (.tau / 16))
                    rotateX(0.35)
                    fill(Color(hue: 0.06 + Double(i) * 0.17, saturation: 0.55, brightness: 0.96))
                    specular(0.35)
                    specularSharpness(40)
                    drawMesh(piece.mesh)
                }
                withBillboard(at: Vector3(0, 1.35, 0)) {
                    fill(.white)
                    textSize(22)
                    textAlign(.center, .middle)
                    drawText(piece.name, 0, 0)
                }
            }
        }

        drawCaption("Two solids, four combinations: union, intersection, and each one cut out of the other")
    }
}
