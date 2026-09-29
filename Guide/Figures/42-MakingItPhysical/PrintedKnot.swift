// figure: frame=0
//
// Guide payoff (Chapter 42): the printed knot, one design made ready for three
// machines. A torus knot swept into a closed tube is drawn the way it will
// leave: its silhouette as one flat color for the first press drum, and its
// hidden-line drawing on top for the pen, with the stretches the knot covers
// dashed so the pen lifts at every gap. The lines are drawn in multiply, the
// way ink lies over ink, so where they cross the pink the screen shows the
// overprint and the separation puts both inks there. The line weight is a
// 0.7 mm pen on the 190 mm a square canvas gets on A4. The seed pins the
// knot's small wobble, and frame 0 is the start of its slow turn, the view
// every export reads unless --frame picks another. A headless render never
// presses S, so the figure writes no file.
import Ollin

final class PrintedKnot: Sketch {
    @Param(2...7) var windings = 3
    @Param(2...7) var turns = 2
    @Param(0.08...0.3) var thickness = 0.18
    @Param(20...120) var millimeters = 70.0

    let blockInk = Ink.fluorescentPink
    let lineInk = Ink.mediumBlue
    override var printInks: [Ink]? { [blockInk, lineInk] }

    override func setup() {
        seed(1207)
    }

    override func draw() {
        background(.white)
        camera(Camera3D(eye: Vector3(0, 2.9, 2.6), target: Vector3(0, -0.3, 0)))
        rotateY(time * 0.1)
        let knot = knotMesh()

        withoutLights {                 // one flat color, for the first drum
            fill(blockInk.color)
            drawMesh(knot)
        }

        let pen = shortSide * 0.7 / 190  // a 0.7 mm pen, on an A4 sheet
        let drawing = lineDrawing(of: knot)
        noFill()
        stroke(lineInk.color)
        strokeWeight(pen)
        strokeCap(.round)
        strokeJoin(.round)
        blendMode(.multiply)            // ink over ink, as the press lays it
        strokeDash(.dashes(pen * 3, gap: pen * 2.5))
        for line in drawing.hidden { drawPolyline(line.points, closed: line.isClosed) }
        noStrokeDash()
        for line in drawing.paths { drawPolyline(line.points, closed: line.isClosed) }
    }

    override func keyPressed() {
        guard key == "s" else { return }
        let solid = knotMesh().normalized(scale: millimeters)
        print(solid.printCheck().summary)
        try? solid.write(to: "knot.3mf")
    }

    /// The knot as a solid: a path that winds `windings` times around and
    /// `turns` times through, nudged by looping noise, swept into a closed tube.
    func knotMesh() -> Mesh {
        let steps = 240
        let path = (0..<steps).map { i -> Vector3 in
            let u = Double(i) / Double(steps)
            let t = u * .tau
            let r = 2 + cos(Double(turns) * t)
            let wobble = Vector3(signedNoise(0, loop: u), signedNoise(4, loop: u),
                                 signedNoise(8, loop: u)) * 0.08
            return Vector3(r * cos(Double(windings) * t), sin(Double(turns) * t),
                           r * sin(Double(windings) * t)) * 0.5 + wobble
        }
        return Mesh.tube(along: path, radius: thickness, sides: 20, closed: true)
    }
}
