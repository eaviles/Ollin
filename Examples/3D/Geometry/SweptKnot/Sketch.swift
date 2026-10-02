import Ollin

/// **A swept knot**: a star carried round a trefoil knot, carriages riding the knot
/// without ever rolling over, and a ribbon round its foot whose rungs can be laid
/// by an even pace.
///
/// The knot is a `Curve3D`, a path through space whose frames turn with the path and
/// never twist about it. `Mesh.sweep` lays the star across the path at every point and
/// joins the copies; `twist` adds turns on purpose, so the star's points wind round
/// the knot the number of times you ask and no more. The carriages ride the same
/// frames with `frame(at:)`: each one faces the way the knot runs and keeps its roof
/// where the frame puts it, through every bend.
///
/// The ribbon is a `Mesh.strip` between two loops that bulge and pinch. Its rungs are
/// striped in fours so their spacing shows. With **even pace** on (the default), the
/// rungs are placed by a `Pace` of the strip's area, so every stripe covers the same
/// area of ribbon however the loops bend. Turn it off and the rungs fall at even
/// steps of the loops' parameter instead: the stripes crowd where the loops slow
/// down and stretch where they speed up.
///
/// Try it: set **turns** to 0 to see a sweep that does not twist at all, or raise
/// **points** to round the star off toward a tube.
@main
final class SweptKnot_Example: Sketch {

    @Param(0 ... 4, icon: "arrow.trianglehead.2.clockwise.rotate.90") var turns = 1
    @Param(3 ... 9, icon: "star") var points = 5
    @Param(0 ... 16, icon: "cablecar") var riders = 7
    @Param(icon: "ruler") var evenPace = true

    private let knot = Curve3D((0..<320).map { k -> Vector3 in
        let t = Double(k) / 320 * .tau
        let r = 1.15 + 0.45 * cos(3 * t)
        return Vector3(r * cos(2 * t), 0.55 * sin(3 * t) + 0.35, r * sin(2 * t))
    }, closed: true)

    private var tube = Mesh(positions: [], indices: [])
    private var ribbon = Mesh(positions: [], indices: [])
    private var built: (turns: Int, points: Int, evenPace: Bool)?

    override func draw() {
        if built.map({ $0 != (turns, points, evenPace) }) ?? true { rebuild() }

        background(Color(hex: 0x0A0B10))
        cameraShowcase(.orbitAndRise(period: 30, rise: 0.3, in: 16),
                       radius: 8.4, elevation: 0.36, fieldOfView: .pi / 3.6)
        directionalLight(.white, direction: Vector3(-0.3, -0.8, -0.5), intensity: 0.9)
        headlight(intensity: 0.45)
        ambientLight(Color(white: 0.25))
        specular(0.4); specularSharpness(48)
        translate(0, 0.55, 0)                              // the knot and ribbon centered

        fill(Color(hex: 0xF2B544))
        drawMesh(tube)

        fill(Color(hex: 0xE4572E))
        for k in 0..<riders {
            let along = (time * 0.03 + Double(k) / Double(riders)).truncatingRemainder(dividingBy: 1)
            let f = knot.frame(at: along)
            withState {
                translate(f.position)
                rotate(f.rotation)                         // z along the knot, y up the frame
                rotateZ(along * Double(turns) * .tau)      // turned as the star is turned there
                translate(0, 0.27, 0)                      // riding the star's top point
                drawBox(width: 0.16, height: 0.1, depth: 0.32)
            }
        }

        fill(.white)
        drawMesh(ribbon)
    }

    private func rebuild() {
        let star = Profile.star(points: points, outerRadius: 0.2, innerRadius: 0.09)
        let wind = Double(turns)
        tube = .sweep(star, along: knot, twist: { $0 * wind * .tau })

        // Two loops round the knot's foot, the ribbon between them tall and far
        // out at two sides and short and close in at the other two, so a plain
        // step of their parameter sweeps about eight times more ribbon in one
        // place than in another.
        func reach(_ t: Double) -> Double { 2.6 + 0.9 * cos(2 * t) }
        func lower(_ t: Double) -> Vector3 {
            Vector3(reach(t) * cos(t), -1.3, reach(t) * sin(t))
        }
        func upper(_ t: Double) -> Vector3 {
            let r = reach(t) * 0.9
            return Vector3(r * cos(t), -1.0 + 0.45 * (1 + cos(2 * t)), r * sin(t))
        }
        let rungs = 240
        let pace = Pace(byAreaBetween: upper, and: lower, period: .tau)
        let ts = (0..<rungs).map { k -> Double in
            let share = Double(k) / Double(rungs)
            return evenPace ? pace.parameter(at: share) : share * .tau
        }
        let colors = (0..<rungs).map { k in
            (k / 4) % 2 == 0 ? Color(hex: 0x5BC0BE) : Color(hex: 0xF4F1E8)
        }
        // Upper line first, so the strip's front (and its normals) faces out.
        ribbon = .strip(between: ts.map(upper), and: ts.map(lower), colors: colors, closed: true)
        built = (turns, points, evenPace)
    }
}
