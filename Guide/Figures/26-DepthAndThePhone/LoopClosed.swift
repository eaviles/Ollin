// figure: frame=0
//
// Guide figure (Chapter 26): a walk that comes back to where it started. The
// camera circles a staged block and returns, with the same small error added to
// its pose every frame. On the left each frame is lined up against the scan
// before it is merged, which is all a sweep can do on its own: the walk still
// closes as a spiral, and the room leans. On the right the scan also recognizes
// the place it began at, and straightens every pose between.
import Ollin
import simd

final class LoopClosed: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    var lined = WorldCloud(voxelSize: 0.05)
    var closed = ScanGraph(voxelSize: 0.05)
    /// Where the left half thinks the camera stood at each kept moment.
    var linedWalk: [Vector3] = []
    var recognized = 0

    override func setup() {
        // A short walk wants its keyframes closer together than a room sweep does,
        // and it does not have to look as far back to find where it began.
        var settings = ScanGraph.Settings()
        settings.keyframeDistance = 0.24
        settings.keyframeTurn = .pi / 18
        settings.keyframeDetail = 0.05
        settings.separation = 14
        closed = ScanGraph(voxelSize: 0.05, settings: settings)

        // What the camera gets wrong each frame: always the same small lean, which
        // is what makes it pile up instead of averaging out.
        var wrong = simd_float4x4(simd_quatf(angle: 0.0105,
                                             axis: simd_normalize(SIMD3<Float>(0.1, 1, 0.1))))
        wrong.columns.3 = SIMD4<Float>(0.011, 0.001, -0.007, 1)

        var drift = matrix_identity_float4x4
        let stations = 46
        for step in 0 ..< stations {
            // A little past a full turn, so the walk really does come home.
            let angle = Double(step) / Double(stations - 1) * 1.35 * .tau
            let eye = Vector3(cos(angle) * 1.5, 1.15, sin(angle) * 1.5)
            // Facing out at the wall, tipped down the way a phone is held. Only the
            // near wall is ever in frame, which is what leaves the walk a lean to
            // find when it comes home.
            let at = eye + Vector3(cos(angle) * 2, -0.5, sin(angle) * 2)
            let frame = StageCamera.capture(eye: eye, target: at)
            let cloud = frame.pointCloud(pointSize: 0.03)
            let reported = drift * StageCamera.pose(eye: eye, target: at)

            let alone = lined.add(cloud, correcting: reported)
            let update = closed.add(cloud, correcting: reported)
            if update.keyframe != nil {
                linedWalk.append(Vector3.zero.transformed(by: alone.pose))
            }
            if update.loop != nil { recognized += 1 }
            drift = drift * wrong
        }
    }

    override func draw() {
        background(Color(hex: 0x0D1017))

        // Straight down on both, orthographic and fixed, so the two halves are
        // drawn at the same size from the same angle. From overhead a wall is a
        // line, and a walk that leaned draws that line twice.
        camera(.orthographic(eye: Vector3(0, 14, 0.001), target: .zero, height: 9.2))
        drawPointCloud(lined.cloud.transformed(by: sideways(-3.2)))
        drawPointCloud(closed.cloud.transformed(by: sideways(3.2)))
        drawWalk(linedWalk, shiftedBy: -3.2)
        drawWalk(closed.keyframes.map { Vector3.zero.transformed(by: $0.pose) }, shiftedBy: 3.2)

        textSize(23)
        textAlign(.center)
        fill(Color(hex: 0xFF8A70))
        drawText("lined up frame by frame", width * 0.25, 40)
        fill(Color(hex: 0x8FE38F))
        drawText("and it knows where it began", width * 0.75, 40)
        textSize(17)
        fill(Color(white: 0.62))
        drawText("\(lined.count) points", width * 0.25, 66)
        drawText("\(closed.count) points, \(recognized) place\(recognized == 1 ? "" : "s") met",
                 width * 0.75, 66)
    }

    /// The walk, as a line of marks that runs from dark to bright. Where the two
    /// ends of it sit is the whole picture: a walk that leaned closes as a spiral.
    private func drawWalk(_ walk: [Vector3], shiftedBy shift: Double) {
        guard walk.count > 1 else { return }
        var trail = PointCloud()
        for (index, at) in walk.enumerated() {
            let along = Double(index) / Double(walk.count - 1)
            let ends = index == 0 || index == walk.count - 1
            trail.points.append(PointCloud.Point(
                position: at + Vector3(shift, 0.8, 0),
                color: ends ? Color(hex: 0xFFFFFF)
                            : Color(red: 1.0, green: 0.42 + along * 0.44, blue: 0.22),
                size: ends ? 0.15 : 0.09))
        }
        drawPointCloud(trail)
    }

    private func sideways(_ x: Double) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(Float(x), 0, 0, 1)
        return m
    }
}

// The stand-in depth camera: rays marched through a staged room on the CPU.
// A real depth source (a recorded clip, a tethered iPhone) hands you the same
// RGBDFrame; only the last few lines here matter to the rest of the chapter.
enum StageCamera {
    static let w = 160, h = 120

    static func capture(eye: Vector3, target: Vector3) -> RGBDFrame {
        let intrinsics = CameraIntrinsics(fx: 140, fy: 140,
                                          cx: Double(w) / 2, cy: Double(h) / 2,
                                          width: w, height: h)
        let f = (target - eye).normalized
        let r = f.cross(Vector3(0, 1, 0)).normalized
        let u = r.cross(f)

        var depths = [Float](repeating: 0, count: w * h)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0 ..< h {
            for col in 0 ..< w {
                let px = (Double(col) + 0.5 - intrinsics.cx) / intrinsics.fx
                let py = -(Double(row) + 0.5 - intrinsics.cy) / intrinsics.fy
                let dirCam = Vector3(px, py, -1).normalized
                let dir = r * dirCam.x + u * dirCam.y - f * dirCam.z
                var t = 0.0
                var hit = false
                for _ in 0 ..< 80 {
                    let d = scene(eye + dir * t)
                    if d < 0.005 { hit = true; break }
                    t += d
                    if t > 9 { break }
                }
                let i = row * w + col
                if hit {
                    depths[i] = Float(-dirCam.z * t)
                    let c = shade(at: eye + dir * t)
                    rgba[i * 4] = UInt8(c.0 * 255)
                    rgba[i * 4 + 1] = UInt8(c.1 * 255)
                    rgba[i * 4 + 2] = UInt8(c.2 * 255)
                    rgba[i * 4 + 3] = 255
                }
            }
        }
        let color = Image(width: w, height: h, premultipliedRGBA: rgba)!
        return RGBDFrame(color: color, depth: depths, confidence: nil,
                         depthWidth: w, depthHeight: h, intrinsics: intrinsics)
    }

    static func pose(eye: Vector3, target: Vector3) -> simd_float4x4 {
        let f = (target - eye).normalized
        let r = f.cross(Vector3(0, 1, 0)).normalized
        let u = r.cross(f)
        func col(_ v: Vector3, _ w: Float) -> simd_float4 {
            simd_float4(Float(v.x), Float(v.y), Float(v.z), w)
        }
        return simd_float4x4(columns: (col(r, 0), col(u, 0), col(f * -1, 0), col(eye, 1)))
    }

    /// A room seen from the inside, with six crates of different sizes standing
    /// around its edge. The crates are not decoration: a camera facing one flat wall
    /// can slide along it and fit it exactly as well, so a match made there would
    /// report three measured numbers and three invented ones.
    static func scene(_ p: Vector3) -> Double {
        var d = -box(p - Vector3(0, 1.5, 0), Vector3(2.7, 1.5, 2.7))
        for corner in 0 ..< 6 {
            let angle = .tau * Double(corner) / 6 + 0.4
            let at = Vector3(cos(angle) * 2.1, 0, sin(angle) * 2.1)
            let edge = 0.22 + 0.08 * Double(corner % 3)
            d = min(d, box(p - at - Vector3(0, edge, 0), Vector3(edge, edge, edge)))
        }
        return d
    }

    private static func box(_ q: Vector3, _ half: Vector3) -> Double {
        let a = Vector3(abs(q.x) - half.x, abs(q.y) - half.y, abs(q.z) - half.z)
        return Vector3(max(a.x, 0), max(a.y, 0), max(a.z, 0)).length
            + min(max(a.x, max(a.y, a.z)), 0)
    }

    static func shade(at p: Vector3) -> (Double, Double, Double) {
        if p.y < 0.02 { return (0.30, 0.32, 0.36) }
        if abs(p.x) > 2.6 || abs(p.z) > 2.6 { return (0.80, 0.56, 0.40) }
        return (0.52, 0.72, 0.58)
    }
}
