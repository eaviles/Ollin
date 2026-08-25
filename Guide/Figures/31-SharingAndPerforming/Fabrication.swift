// figure: frame=0 themed
//
// Guide listing (Chapter 31): why a printable mesh needs checking rather than
// looking at. Two copies of the same torus knot, one swept closed and one left
// open at the ends. They are the same shape from here, and only one of them is
// a solid. The labels are read from printCheck() rather than typed, so they
// cannot drift from what the writers would actually report, and they sit under
// each knot by projecting its own center back onto the canvas.
import Ollin
import OllinDiagram

final class Fabrication: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    /// Where each copy stands, in world units either side of the middle.
    private let offset = 1.6

    /// The knot path both copies are swept along.
    private var path: [Vector3] {
        (0 ..< 260).map { i in
            let t = Double(i) / 260 * .tau
            let around = 3 * t, through = 2 * t
            return Vector3((2 + cos(through)) * cos(around),
                           sin(through),
                           (2 + cos(through)) * sin(around)) * 0.3
        }
    }

    override func draw() {
        background(paper)
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        perspective(eye: Vector3(0, 2.5, 3.9), target: Vector3(0, 0.15, 0))

        let closed = Mesh.tube(along: path, radius: 0.16, sides: 18, closed: true)
        let open = Mesh.tube(along: path, radius: 0.16, sides: 18, closed: false)

        fill(Color(hex: 0xC9A227))
        material(.metal(roughness: 0.3))
        for (mesh, side) in [(closed, -offset), (open, offset)] {
            withState {
                translate(side, 0, 0)
                drawMesh(mesh)
            }
        }

        label(closed, at: -offset)
        label(open, at: offset)
    }

    /// The verdict under one copy, taken from the check itself and placed under
    /// the knot it belongs to.
    private func label(_ mesh: Mesh, at side: Double) {
        guard let anchor = project(Vector3(side, 0, 0)) else { return }
        let check = mesh.printCheck()

        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textAlign(.center, .top)

            textSize(21)
            fill(ink)
            drawText(check.isClosed ? "closed" : "open at the ends", anchor.x, height * 0.78)

            textSize(17)
            if check.isPrintable {
                fill(Color(hex: darkTheme ? 0x5BAD7C : 0x2F7D4F))
                drawText("ready to print", anchor.x, height * 0.855)
            } else {
                fill(Color(hex: darkTheme ? 0xE0684A : 0xC2431E))
                drawText("\(check.boundaryEdgeCount) edges border a hole",
                         anchor.x, height * 0.855)
            }
        }
    }
}
