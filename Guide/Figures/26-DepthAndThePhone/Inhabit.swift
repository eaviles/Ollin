// figure: frame=0
//
// Guide figure (Chapter 26): drawing inside a depth scene. The stand-in
// camera's frame is drawn as a metric depth scene, and solid spheres placed
// in meters are occluded by the room exactly where they pass behind it.
import Ollin

final class Inhabit: Sketch {
    override var canvasSize: CanvasSize { .size(800, 600) }

    var frame: RGBDFrame?

    override func setup() {
        frame = StageCamera.capture(eye: Vector3(0.2, 1.05, 1.7),
                                    target: Vector3(0, 0.45, -1.1))
    }

    override func draw() {
        background(.black)
        guard let frame else { return }

        // A camera built from the feed's own lens: one metric space.
        camera(.fromIntrinsics(frame.intrinsics))
        drawDepthScene(frame)

        // A run of marbles marching into the room, in meters. The ones that
        // pass behind the ball and the crate are hidden by the feed's depth.
        for i in 0 ..< 6 {
            withState {
                translate(-1.3 + Double(i) * 0.44, -0.32, -1.85 - Double(i) * 0.34)
                fill(Color(hue: 0.09 + Double(i) * 0.035, saturation: 0.75, brightness: 1))
                specular(0.5); shininess(60)
                drawSphere(radius: 0.12)
            }
        }
    }
}

// The stand-in depth camera: rays marched through a staged room on the CPU.
// A real depth source (a recorded clip, a tethered iPhone) hands you the same
// RGBDFrame; only the last few lines here matter to the rest of the chapter.
enum StageCamera {
    static let w = 240, h = 180

    static func capture(eye: Vector3, target: Vector3) -> RGBDFrame {
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
                    let c = shade(at: p)
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
