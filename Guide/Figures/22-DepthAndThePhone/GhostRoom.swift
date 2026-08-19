// figure: frame=300
//
// Guide payoff (Chapter 22): GhostRoom. A sweep of nine frames from the
// stand-in depth camera assembles into one world cloud, one frame joining
// every second, drawn as additive light: a room scanning itself into being.
import Ollin
import simd

final class GhostRoom: Sketch {
    let room = Vector3(-0.1, 0.4, -1.2)
    var world = WorldCloud(voxelSize: 0.012)
    var fused = 0

    override func draw() {
        background(Color(hex: 0x05070C))

        // One more frame of the sweep joins the world every 60 frames.
        let due = min(9, frameCount / 60 + 1)
        while fused < due {
            let a = -1.15 + Double(fused) * 0.29
            let eye = Vector3(room.x + sin(a) * 3.0, 1.1 + Double(fused % 3) * 0.25,
                              room.z + cos(a) * 3.0)
            let frame = StageCamera.capture(eye: eye, target: room)
            world.add(frame.pointCloud(pointSize: 0.011),
                      transformedBy: StageCamera.pose(eye: eye, target: room))
            fused += 1
        }

        cameraShowcase(target: room + Vector3(0, 0.2, 0), radius: 5.8,
                       elevation: 0.4, fieldOfView: .pi / 4)
        blendMode(.add)
        drawPointCloud(world.cloud)
        blendMode(.normal)
    }
}

// The stand-in depth camera: rays marched through a staged room on the CPU.
// A real depth source (a recorded clip, a tethered iPhone) hands you the same
// RGBDFrame; only the last few lines here matter to the rest of the chapter.
enum StageCamera {
    static let w = 240, h = 180

    static func capture(eye: Vector3, target: Vector3, tint: Color? = nil) -> RGBDFrame {
        let intrinsics = CameraIntrinsics(fx: 210, fy: 210,
                                          cx: Double(w) / 2, cy: Double(h) / 2,
                                          width: w, height: h)
        // The camera's basis: forward to the target, right, and up.
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
                // March until the room is hit.
                var t = 0.0
                var hit = false
                for _ in 0 ..< 96 {
                    let d = scene(eye + dir * t)
                    if d < 0.004 { hit = true; break }
                    t += d
                    if t > 12 { break }
                }
                let i = row * w + col
                if hit {
                    depths[i] = Float(-dirCam.z * t)
                    let p = eye + dir * t
                    var c = shade(at: p)
                    if let tint { c = (c.0 * tint.red, c.1 * tint.green, c.2 * tint.blue) }
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

    // The camera-to-world pose for a capture: where it stood, which way it looked.
    static func pose(eye: Vector3, target: Vector3) -> simd_float4x4 {
        let f = (target - eye).normalized
        let r = f.cross(Vector3(0, 1, 0)).normalized
        let u = r.cross(f)
        func col(_ v: Vector3, _ w: Float) -> simd_float4 {
            simd_float4(Float(v.x), Float(v.y), Float(v.z), w)
        }
        return simd_float4x4(columns: (col(r, 0), col(u, 0), col(f * -1, 0), col(eye, 1)))
    }

    // The staged room: a floor, two walls, a ball, and a crate.
    static func scene(_ p: Vector3) -> Double {
        let floor = p.y
        let back = p.z + 2.4
        let left = p.x + 2.4
        let ball = (p - Vector3(-0.5, 0.45, -1.1)).length - 0.45
        let q = p - Vector3(0.78, 0.3, -1.5)
        let a = Vector3(abs(q.x) - 0.3, abs(q.y) - 0.3, abs(q.z) - 0.3)
        let crate = Vector3(max(a.x, 0), max(a.y, 0), max(a.z, 0)).length
            + min(max(a.x, max(a.y, a.z)), 0)
        return min(min(floor, back), min(left, min(ball, crate)))
    }

    // Flat colors per surface, shaded by one light.
    static func shade(at p: Vector3) -> (Double, Double, Double) {
        let e = 0.002
        let n = Vector3(scene(p + Vector3(e, 0, 0)) - scene(p - Vector3(e, 0, 0)),
                        scene(p + Vector3(0, e, 0)) - scene(p - Vector3(0, e, 0)),
                        scene(p + Vector3(0, 0, e)) - scene(p - Vector3(0, 0, e))).normalized
        let light = Vector3(0.45, 1, 0.35).normalized
        let lit = 0.35 + 0.65 * max(0, n.dot(light))

        var base = (0.78, 0.74, 0.68)                       // floor and walls
        if (p - Vector3(-0.5, 0.45, -1.1)).length < 0.47 { base = (0.89, 0.34, 0.18) }
        let q = p - Vector3(0.78, 0.3, -1.5)
        if max(abs(q.x), max(abs(q.y), abs(q.z))) < 0.34 { base = (0.17, 0.55, 0.53) }
        if p.y < 0.012 {                                    // checker the floor
            let c = (Int((p.x + 8).rounded(.down)) + Int((p.z + 8).rounded(.down))) % 2
            base = c == 0 ? (0.8, 0.76, 0.7) : (0.68, 0.64, 0.59)
        }
        return (base.0 * lit, base.1 * lit, base.2 * lit)
    }
}
