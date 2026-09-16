//  Inspired by the live demo of Domenico Bruzzese's *Blurry* (2019), a depth-of-field
//  lines renderer, MIT: https://github.com/Domenicobrz/Blurry, live at
//  https://domenicobrz.github.io/webgl/projects/DOFlinesrenderer/. The scene is
//  built from the demo's description, not ported from its source. The lens
//  technique is Anders Hoff's (https://inconvergent.net/2019/depth-of-field/).

import Ollin

/// Lines of light through a real lens: `LineSpray` on a sphere of a hundred
/// and fifty rings of latitude, nudged by a curl field, lit from one side, with
/// a burst of bright spokes at its center.
///
/// The scene is a list of `SprayLine`s built once; `LineSpray` does the rest
/// each frame: a pass of points scattered along the lines and through the
/// `Bokeh` lens on the GPU, added into a running mean, printed through
/// `developed` (exposure, a Reinhard roll-off, then the warm black ground added
/// after the curve). The camera, lens, and print are parameters, and moving any
/// of them restarts the average, which is what a photograph through a lens
/// would do. The canvas is the source demo's own viewport, so the picture can
/// be measured against it.
@main
final class LineSpray_Example: Sketch {
    override var canvasSize: CanvasSize { .size(1919, 1003) }

    // The camera: 49 units out along (-5, -5, 10), through a 20-degree lens.
    @Param("Azimuth", -180 ... 180) var azimuth = -26.57
    @Param("Elevation", -80 ... 80) var elevation = -24.09
    @Param("Distance", 20 ... 120) var distance = 49.0
    @Param("Field of view", 5 ... 60) var fieldOfView = 20.0
    /// Turn the camera around the sphere at six degrees a second. Every frame
    /// then restarts the average, so an export of the turn wants `--settle N`
    /// to draw each written frame several times with the clock held.
    @Param("Turn") var turning = false

    // The lens.
    @Param("Focal distance", 20 ... 80) var focalDistance = 49.19
    @Param("Bokeh", 0 ... 0.3) var bokeh = 0.095
    @Param("Minimum size", 0 ... 0.1) var minimumSize = 0.015
    @Param("Passes per frame", 1 ... 10) var passesPerFrame = 5

    // The print: an exposure gain over the mean, then the ground.
    @Param("Exposure", 50 ... 2000) var exposure = 526.0
    @Param("Ground") var ground = Color(red: 21 / 255, green: 16 / 255, blue: 16 / 255)

    private var spray: LineSpray!

    override func setup() {
        seed(3)
        // Twenty-five points per line per pass.
        spray = makeLineSpray(buildScene(), sampling: .perLine(25), passesPerFrame: passesPerFrame)
    }

    override func draw() {
        background(.black)
        let turn = turning ? time * 6 : 0
        camera(.orbiting(target: .zero, radius: distance,
                         azimuth: (azimuth + turn) * .pi / 180, elevation: elevation * .pi / 180,
                         fieldOfView: fieldOfView * .pi / 180, near: 2, far: 200))
        spray.bokeh = Bokeh(focalDistance: focalDistance, strength: bokeh, minSize: minimumSize)
        spray.passesPerFrame = passesPerFrame
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: exposure, ground: ground).image, 0, 0)
    }

    // MARK: - The scene

    /// A hundred and fifty rings of latitude on a sphere of radius 5.75, each cut
    /// into segments in proportion to its size, every vertex pushed by a curl
    /// field, lit by one light with a cubed cosine and a faint floor. Now and
    /// then a segment sits a little further out, and now and then a vertex sends
    /// a spoke inward toward the center, twice as bright as the ring (six times,
    /// for a few), which is what piles into the burst at the middle.
    private func buildScene() -> [SprayLine] {
        var lines: [SprayLine] = []
        let rings = 150
        let sphereRadius = 5.75
        let light = Vector3(0.2, 0.35, 0.5).normalized

        for j in 0 ..< rings {
            let latitude = Double(j) / Double(rings) * .pi
            let ringRadius = -sin(latitude)      // (0, 0, 1) turned about x by the latitude
            let z = cos(latitude)
            let segments = 70 + Int(abs(floor(ringRadius * 360)))

            for i in 0 ..< segments {
                let a1 = Double(i) / Double(segments) * .tau
                let a2 = Double(i + 1) / Double(segments) * .tau
                let r = random() > 0.92 ? sphereRadius + 0.15 : sphereRadius
                let p1 = Vector3(cos(a1) * ringRadius * r, sin(a1) * ringRadius * r, z * r)
                let p2 = Vector3(cos(a2) * ringRadius * r, sin(a2) * ringRadius * r, z * r)
                let q1 = p1 + displacement(p1)
                let q2 = p2 + displacement(p2)

                let normal = p1.normalized
                let diffuse = pow(max(normal.dot(light), 0), 3)
                let radiance = 0.1 * diffuse + 0.002
                lines.append(line(q1, q2, radiance))

                if random() > 0.975 {
                    let boost = random() > 0.8 ? 6.0 : 2.0
                    let inner = 0.1 + random() * 0.3
                    let outer = inner + pow(random(), 2) * 0.25
                    lines.append(line(q1 * inner, q1 * outer, boost * radiance))
                }
            }
        }
        return lines
    }

    /// The nudge a vertex takes: the direction of the curl field at the point,
    /// scaled by a slower field of the same kind so the strength varies across
    /// the sphere. A curl only ever swirls, so the rings bend as if a current
    /// had passed through them rather than tearing.
    private func displacement(_ p: Vector3) -> Vector3 {
        let strength = 0.1 + curlNoise(p * 0.15).normalized.x * 0.7
        return curlNoise(p * 0.5).normalized * strength
    }

    /// A white line of the given radiance: the tone is white and the intensity
    /// carries the light.
    private func line(_ a: Vector3, _ b: Vector3, _ radiance: Double) -> SprayLine {
        SprayLine(from: a, to: b, color: .white, intensity: radiance)
    }
}
