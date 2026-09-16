//  Inspired by the live demo of Domenico Bruzzese's *Blurry* (2019), a depth-of-field
//  lines renderer, MIT: https://github.com/Domenicobrz/Blurry, live at
//  https://domenicobrz.github.io/webgl/projects/DOFlinesrenderer/. The scene is
//  built from the demo's description, not ported from its source. The lens
//  technique is Anders Hoff's (https://inconvergent.net/2019/depth-of-field/).

import Foundation
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
///
/// `Drift` bends the scene again every frame, the curl field's sample point
/// touring a circle so the sphere breathes and returns home every lap. The
/// bend runs on every core through `noiseFields`, the sketch's fields as a
/// value, and `setLines` rewrites the GPU records in place, so a frame of forty
/// thousand moving lines costs a few milliseconds rather than a hundred.
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

    /// Re-bend the scene every frame, the field's sample point touring a circle
    /// of `driftRadius` once every twelve seconds. Every frame then restarts the
    /// average, so an export of the drift wants `--settle N` like the turn.
    @Param("Drift") var drifting = false
    @Param("Drift radius", 0 ... 2) var driftRadius = 0.4

    private var spray: LineSpray!
    /// The scene before the bend: what every frame re-bends from.
    private var sources: [Source] = []

    override func setup() {
        seed(3)
        sources = buildScene()
        // Twenty-five points per line per pass.
        spray = makeLineSpray(bent(offset: .zero), sampling: .perLine(25), passesPerFrame: passesPerFrame)
    }

    override func draw() {
        background(.black)
        let turn = turning ? time * 6 : 0
        camera(.orbiting(target: .zero, radius: distance,
                         azimuth: (azimuth + turn) * .pi / 180, elevation: elevation * .pi / 180,
                         fieldOfView: fieldOfView * .pi / 180, near: 2, far: 200))
        spray.bokeh = Bokeh(focalDistance: focalDistance, strength: bokeh, minSize: minimumSize)
        spray.passesPerFrame = passesPerFrame
        if drifting {
            let lap = loopProgress(over: 12) * .tau
            spray.setLines(bent(offset: Vector3(cos(lap), sin(lap), 0) * driftRadius))
        }
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: exposure, ground: ground).image, 0, 0)
    }

    // MARK: - The scene

    /// One line of the scene before the bend: a ring segment between two
    /// vertices of the sphere, or a spoke sent inward from one, each with its
    /// light. The bend moves the vertices; a spoke follows its vertex.
    private enum Source {
        case ring(Vector3, Vector3, radiance: Double)
        case spoke(Vector3, inner: Double, outer: Double, radiance: Double)
    }

    /// A hundred and fifty rings of latitude on a sphere of radius 5.75, each cut
    /// into segments in proportion to its size, lit by one light with a cubed
    /// cosine and a faint floor. Now and then a segment sits a little further
    /// out, and now and then a vertex sends a spoke inward toward the center,
    /// twice as bright as the ring (six times, for a few), which is what piles
    /// into the burst at the middle. Every random choice is made here, once, so
    /// the bend can be redone every frame over the same scene.
    private func buildScene() -> [Source] {
        var sources: [Source] = []
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

                let normal = p1.normalized
                let diffuse = pow(max(normal.dot(light), 0), 3)
                let radiance = 0.1 * diffuse + 0.002
                sources.append(.ring(p1, p2, radiance: radiance))

                if random() > 0.975 {
                    let boost = random() > 0.8 ? 6.0 : 2.0
                    let inner = 0.1 + random() * 0.3
                    let outer = inner + pow(random(), 2) * 0.25
                    sources.append(.spoke(p1, inner: inner, outer: outer, radiance: boost * radiance))
                }
            }
        }
        return sources
    }

    /// The scene bent by the curl field read at `offset` from every vertex, one
    /// `SprayLine` per source, every core taking a slice. The fields are a
    /// value, so the threads read exactly the field the sketch reads, seeded as
    /// it is.
    private func bent(offset: Vector3) -> [SprayLine] {
        let fields = noiseFields
        let sources = self.sources
        var lines = [SprayLine](repeating: SprayLine(from: .zero, to: .zero), count: sources.count)
        lines.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: sources.count) { i in
                switch sources[i] {
                case .ring(let p1, let p2, let radiance):
                    let q1 = p1 + displacement(p1 + offset, in: fields)
                    let q2 = p2 + displacement(p2 + offset, in: fields)
                    out[i] = SprayLine(from: q1, to: q2, color: .white, intensity: radiance)
                case .spoke(let p1, let inner, let outer, let radiance):
                    let q1 = p1 + displacement(p1 + offset, in: fields)
                    out[i] = SprayLine(from: q1 * inner, to: q1 * outer, color: .white, intensity: radiance)
                }
            }
        }
        return lines
    }
}

/// The nudge a vertex takes: the direction of the curl field at the point,
/// scaled by a slower field of the same kind so the strength varies across the
/// sphere. A curl only ever swirls, so the rings bend as if a current had
/// passed through them rather than tearing. A free function, so the threads of
/// `bent(offset:)` can call it with nothing of the sketch in hand.
private func displacement(_ p: Vector3, in fields: NoiseFields) -> Vector3 {
    let strength = 0.1 + fields.curlNoise(p * 0.15).normalized.x * 0.7
    return fields.curlNoise(p * 0.5).normalized * strength
}
