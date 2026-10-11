import Ollin

/// **Lofted vessels**: a bottle, a horn, and a boat hull, each one surface through
/// several flat shapes placed along a path.
///
/// A sweep carries one shape along a path. A loft (`Mesh.loft`) carries several, one
/// after another, and blends the surface from each to the next. The bottle runs up
/// a straight spine from a polygon foot through a round belly to a narrow neck and a
/// lip; the horn follows a bending spine from a star to a circle, turning on the
/// way; the hull is a sheet through open U-shaped ribs from bow to stern, so it has
/// no caps and an inside you can see into.
///
/// Every section is laid exactly where it was asked for, corners and all, and the
/// outlines are matched round their lengths with each seam turned to the nearest
/// start, so the skin does not twist on its own. With **smoothed** on, the surface
/// runs as a smooth curve through the sections; off, it runs straight from rib to
/// rib, and the stations show as soft ridges.
///
/// Try it: give the foot three **sides** for a triangular bottle, or eight for one
/// that is nearly round all the way up; widen the **belly** and narrow the **neck**.
@main
final class LoftedVessels_Example: Sketch {

    @Param(3 ... 8, icon: "square") var sides = 4
    @Param(0.5 ... 1.1, icon: "circle") var belly = 0.9
    @Param(0.12 ... 0.4, icon: "circle.dotted") var neck = 0.22
    @Param(icon: "scribble.variable") var smoothed = true

    private var bottle = Mesh(positions: [], indices: [])
    private var horn = Mesh(positions: [], indices: [])
    private var hull = Mesh(positions: [], indices: [])
    private var built: (sides: Int, belly: Double, neck: Double, smoothed: Bool)?

    override func draw() {
        if built.map({ $0 != (sides, belly, neck, smoothed) }) ?? true { rebuild() }

        background(Color(hex: 0x0B0C12))
        cameraShowcase(.orbitAndRise(period: 36, rise: 0.25, in: 18),
                       radius: 9.6, elevation: 0.3, fieldOfView: .pi / 3.8)
        directionalLight(.white, direction: Vector3(-0.4, -0.75, -0.5), intensity: 1.0)
        headlight(intensity: 0.35)
        ambientLight(Color(white: 0.24))
        specular(0.4); specularSharpness(44)

        // The three stand on one floor, at the corners of a triangle, so the
        // orbit never hides two behind the third for long.
        withState {
            translate(-2.5, -1.4, 1.1)
            fill(Color(hex: 0x6FC3DF))
            drawMesh(bottle)
        }
        withState {
            translate(2.3, -1.4, 0.9)
            fill(Color(hex: 0xF2B544))
            drawMesh(horn)
        }
        withState {
            translate(0, -0.55, -1.9)
            rotateY(0.35)
            fill(Color(hex: 0xE4572E))
            drawMesh(hull)
        }
    }

    private func rebuild() {
        // The bottle: a polygon foot, a round belly, a narrow neck, and a lip,
        // up a straight spine. Sections are listed with where each sits.
        let spine = Curve3D((0...48).map { Vector3(0, Double($0) / 48 * 3.0, 0) })
        let foot = Profile.polygon(sides: sides, radius: 0.72)
        let round = { (r: Double) in Profile.ellipse(radiusX: r, radiusY: r, segments: 40) }
        bottle = .loft([foot, round(belly), round(belly * 0.92), round(neck), round(neck * 1.25), round(neck * 1.25)],
                       along: spine, at: [0, 0.3, 0.52, 0.76, 0.9, 1], smoothed: smoothed)

        // The horn: a star that rounds into a circle along a bending spine,
        // turning half a turn on the way and shrinking toward its tip.
        let bend = Curve3D(curveThrough: [Vector3(0, 0, 0), Vector3(0.4, 1.2, 0.3), Vector3(-0.3, 2.2, -0.2),
                                          Vector3(0.6, 3.0, 0.2)], segments: 16)
        horn = .loft([Profile.star(points: 6, outerRadius: 0.75, innerRadius: 0.42),
                      Profile.ellipse(radiusX: 0.55, radiusY: 0.55, segments: 36),
                      Profile.ellipse(radiusX: 0.3, radiusY: 0.3, segments: 36)],
                     along: bend, smoothed: smoothed, scale: { 1 - 0.55 * $0 }, twist: { $0 * .pi })

        // The hull: open U-shaped ribs from the bow to the stern, lofted as a
        // sheet with no caps. Each rib is a few points in the frame's plane,
        // x across the boat and y up, drawn from the port gunwale down round
        // the keel and up to starboard.
        func rib(halfBeam: Double, depth: Double, flare: Double) -> Shape {
            Shape(contours: [Contour([Vector2(-halfBeam - flare, 0.7), Vector2(-halfBeam, 0.25),
                                      Vector2(-halfBeam * 0.55, -depth * 0.8), Vector2(0, -depth),
                                      Vector2(halfBeam * 0.55, -depth * 0.8), Vector2(halfBeam, 0.25),
                                      Vector2(halfBeam + flare, 0.7)], closed: false)])
        }
        let keel = Curve3D((0...40).map { Vector3(-1.6 + Double($0) / 40 * 3.2, 0, 0) })
        hull = .loft([rib(halfBeam: 0.02, depth: 0.2, flare: 0.02), rib(halfBeam: 0.4, depth: 0.65, flare: 0.2),
                      rib(halfBeam: 0.66, depth: 0.85, flare: 0.18), rib(halfBeam: 0.62, depth: 0.76, flare: 0.12),
                      rib(halfBeam: 0.44, depth: 0.56, flare: 0.08)],
                     along: keel, at: [0, 0.2, 0.5, 0.78, 1], smoothed: smoothed)
        built = (sides, belly, neck, smoothed)
    }
}
