import Ollin

/// **Hidden lines**: ten thousand small boxes turning in a block of air, drawn the
/// way a draughtsman draws a solid: white faces, and in ink only the edges a box
/// has, the near boxes hiding the edges of the far ones.
///
/// `featureEdges()` is the whole of the look. Under it a mesh draws its faces in
/// the fill as usual, and over them the lines that describe its form: the creases,
/// where two faces meet at more than an angle, and the silhouette where the surface
/// turns away. A box gives its twelve edges and none of the diagonals its faces are
/// built from. The boxes are one `drawMesh(_:instances:)` call, so their edges are
/// one more draw on the GPU, placed by the same matrices; the weight is in canvas
/// points, a hairline on every box however far away it is.
///
/// Each box turns by the noise at its own place in the block, read from
/// `signedNoise(x, y, z, loop:)`, the three-dimensional field that comes back to
/// where it started once a lap: the block churns for **period** seconds and the
/// last frame meets the first. The camera goes once round the block in the same
/// lap.
///
/// Try it: drop **crease** toward zero and every edge counts as a crease, the
/// diagonals included; raise **tumble** for a block that boils; thicken **weight**
/// for a poster, or take it to zero to see the solids alone.
@main
final class HiddenLines_Example: Sketch {

    @Param(6 ... 24, icon: "cube") var side = 22
    @Param(0 ... 3, icon: "lineweight") var weight = 1.0
    @Param(0 ... 1.5, icon: "angle") var crease = 0.5
    @Param(0 ... 3, icon: "rotate.3d") var tumble = 1.2
    @Param(4 ... 30, icon: "timer") var period = 16.0

    private let box = Mesh.box(size: 1)

    override var loopDuration: Double? { period }

    override func draw() {
        background(.white)
        let lap = loopProgress(over: period)
        let turn = lap * 2 * .pi + 0.6       // starting off the grid's rows
        perspective(eye: Vector3(cos(turn) * 25, 12, sin(turn) * 25), target: Vector3(0, -0.6, 0),
                    fieldOfView: .pi / 4.6)
        noLights()
        fill(.white)
        stroke(Color(white: 0.08))
        strokeWeight(weight)
        featureEdges(creaseAngle: crease)

        let spacing = 11.0 / Double(side)
        let middle = Double(side - 1) / 2
        var copies: [MeshInstance] = []
        copies.reserveCapacity(side * side * side)
        for i in 0 ..< side {
            for j in 0 ..< side {
                for k in 0 ..< side {
                    let p = Vector3(Double(i) - middle, Double(j) - middle, Double(k) - middle) * spacing
                    let q = p * 0.16
                    let a = signedNoise(q.x, q.y, q.z, loop: lap, radius: 0.7) * .pi * tumble
                    let b = signedNoise(q.x + 41.3, q.y, q.z, loop: lap, radius: 0.7) * .pi * tumble
                    copies.append(MeshInstance(position: p, rotation: Vector3(a, b, a * 0.6),
                                               scale: spacing * 0.42))
                }
            }
        }
        drawMesh(box, instances: copies)
    }
}
