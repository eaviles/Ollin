import Ollin

/// A block carved by taking other solids out of it: the shape nobody would
/// model by hand, and nobody has to.
///
/// The piece is twelve cuts in three kinds. A cube kept only where a ball
/// overlaps it rounds
/// every edge and corner at once, which is a fillet you get for free rather
/// than a tool you reach for. Then a shaft is bored along each axis, and a
/// smaller block is taken out of each of the eight corners. What comes back is one closed solid, so it
/// draws like any mesh and writes out for a printer like any mesh.
///
/// The cutting runs in `setup()` and again only when a parameter moves, never in
/// `draw()`. That is the shape of the work: cutting is CPU geometry, measured in
/// tenths of a second on a piece this size, while drawing the result costs
/// nothing at all. Turn `roundness` down for a hard-edged block, `bore` up until
/// the shafts meet in the middle and the piece becomes a cage.
@main
final class Carved: Sketch {
    override var loopDuration: Double? { 20 }

    /// How much of the cube the ball keeps: low is a sharp block, high leaves
    /// little but the ball itself.
    @Param(0.55 ... 0.95, icon: "circle.circle") var roundness = 0.68
    /// The radius of the three shafts, as a fraction of the block.
    @Param(0.05 ... 0.34, icon: "circle.dashed") var bore = 0.22
    /// How deep the corner blocks bite.
    @Param(0 ... 0.5, icon: "cube") var corners = 0.3

    private var piece = Mesh(positions: [], indices: [])
    private var carvedFrom = Vector3.zero

    override func setup() {
        cutThePiece()
    }

    /// Cut the piece from scratch. The cuts stack: each result is the solid the
    /// next cutter goes into.
    private func cutThePiece() {
        let size = 2.0
        var block = Mesh.box(size: size)
            .intersection(Mesh.sphere(radius: size * roundness, segments: 32, rings: 16))

        // A shaft through each axis. The cylinder stands along y, so the other
        // two are the same solid given a quarter turn. Turn it, never mirror it:
        // swapping two coordinates reflects the mesh, which leaves it wound
        // inside out, and a cutter that is inside out keeps what it should take.
        let shaft = Mesh.cylinder(radius: size * bore, height: size * 1.6, segments: 28)
        block = block.subtracting(shaft)
        block = block.subtracting(shaft.mapPositions { Vector3($0.y, -$0.x, $0.z) })
        block = block.subtracting(shaft.mapPositions { Vector3($0.x, $0.z, -$0.y) })

        if corners > 0.01 {
            let bite = Mesh.box(size: size * corners)
            for x in [-1.0, 1.0] {
                for y in [-1.0, 1.0] {
                    for z in [-1.0, 1.0] {
                        let at = Vector3(x, y, z) * (size / 2)
                        block = block.subtracting(bite.mapPositions { $0 + at })
                    }
                }
            }
        }

        piece = block
        carvedFrom = Vector3(roundness, bore, corners)
    }

    override func draw() {
        // Re-cut only when a parameter has actually moved.
        if carvedFrom != Vector3(roundness, bore, corners) { cutThePiece() }

        background(Color(hex: 0x0C0D12))
        cameraShowcase(.autoOrbit(period: 20), target: .zero, radius: 5.2,
                       elevation: 0.3, fieldOfView: .pi / 4)

        fill(Color(hex: 0xE8D8BE))
        material(.ceramic)
        drawMesh(piece)

        drawCaption("One block, twelve cuts: rounded by a ball, bored three ways, bitten at every corner")
    }
}
