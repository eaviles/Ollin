// figure: frame=0
//
// Guide diagram (Chapter 27): the anatomy of an RGBD frame. A stand-in depth
// camera (a small CPU ray march over a staged room) produces the same three
// parts a real depth camera streams: a color image, a metric depth map, and
// the lens intrinsics that tie them together.
import Ollin

final class Anatomy: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    var frame: RGBDFrame?

    override func setup() {
        frame = StageCamera.capture(eye: Vector3(0.2, 1.05, 1.7),
                                    target: Vector3(0, 0.45, -1.1))
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        guard let frame else { return }

        let ink = Color(hex: 0x2B2B2B)
        let panel = Rectangle(x: 40, y: 96, width: 360, height: 270)
        let panel2 = Rectangle(x: 440, y: 96, width: 360, height: 270)

        drawImage(frame.color, in: panel)
        drawImage(depthImage(of: frame), in: panel2)

        fill(ink)
        textSize(26)
        textAlign(.left, .middle)
        drawText("color (\(frame.color.width) × \(frame.color.height))", panel.x, 70)
        drawText("depth (meters, \(frame.depthWidth) × \(frame.depthHeight))", panel.x + 400, 70)
        textSize(24)
        let i = frame.intrinsics
        drawText("+ intrinsics: the lens that ties them together", 40, 420)
        fill(ink.withAlpha(0.65))
        drawText("fx \(Int(i.fx))   fy \(Int(i.fy))   cx \(Int(i.cx))   cy \(Int(i.cy))", 40, 456)
        drawText("(focal lengths and image center, in depth-map pixels)", 40, 492)
    }

    // The depth map drawn as a picture: near is bright, far is dark.
    func depthImage(of frame: RGBDFrame) -> Image {
        var rgba = [UInt8]()
        rgba.reserveCapacity(frame.depth.count * 4)
        for d in frame.depth {
            let t = d > 0 ? max(0, min(1, 1 - (Double(d) - 1.2) / 3.2)) : 0
            let v = UInt8(t * 255)
            rgba.append(contentsOf: [v, v, v, 255])
        }
        return Image(width: frame.depthWidth, height: frame.depthHeight,
                     premultipliedRGBA: rgba)!
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
