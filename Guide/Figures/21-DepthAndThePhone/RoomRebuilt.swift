// figure: frame=0
//
// Guide figure (Chapter 21): the fused sweep rebuilt as a solid surface.
// Eight frames of the staged room corner are fused into one world cloud,
// then reconstructSurface turns the cloud into a mesh, oriented by the
// camera positions the sweep was taken from. Where no frame reached, the
// surface honestly stops: the torn rim is the edge of the sweep.
import Ollin
import simd

final class RoomRebuilt: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let room = Vector3(-0.1, 0.4, -1.2)
    lazy var rebuilt = build()

    private func build() -> (mesh: Mesh, eyes: [Vector3]) {
        var world = WorldCloud(voxelSize: 0.02)
        var eyes: [Vector3] = []
        // A real sweep moves around and up and down; the height variation is
        // what covers the tops of things at a healthy angle instead of
        // grazing them.
        for i in 0 ..< 8 {
            let a = -1.3 + Double(i) * 0.38
            let eye = Vector3(room.x + sin(a) * 3.0,
                              1.0 + Double(i % 3) * 0.75,
                              room.z + cos(a) * 3.0)
            let frame = StageCamera.capture(eye: eye, target: room)
            world.add(frame.pointCloud(pointSize: 0.011),
                      transformedBy: StageCamera.pose(eye: eye, target: room))
            eyes.append(eye)
        }
        // A real scan crops to the room of interest before reconstructing:
        // the staged planes run far past the corner, and the reconstruction
        // spends its grid over the whole cloud's bounds.
        let kept = world.cloud.points.map(\.position)
            .filter { $0.x < 2.0 && $0.z < 1.6 && $0.y < 2.2 }
        let mesh = reconstructSurface(of: kept, spacing: world.voxelSize * 2,
                                      resolution: 150, orientedToward: eyes)
        return (mesh, eyes)
    }

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: room + Vector3(0, 0.1, 0), radius: 5.4,
                         azimuth: 0.6, elevation: 0.5, fieldOfView: .pi / 4))
        lightingPreset(.studio)

        fill(Color(hex: 0xD8CFC2))
        material(.dielectric(roughness: 0.55))
        drawMesh(rebuilt.mesh)

        // Where the sweep stood.
        for eye in rebuilt.eyes {
            withState {
                translate(eye.x, eye.y, eye.z)
                fill(Color(hex: 0x86B8FF)); specular(0.3)
                drawSphere(radius: 0.07)
            }
        }
    }
}

// The stand-in depth camera from the chapter's earlier figures: rays marched
// through a staged room on the CPU, handed back as the same RGBDFrame a real
// depth source produces.
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
                // A depth sensor returns nothing at extreme grazing angles
                // (real confidence maps encode exactly this), so the stand-in
                // declines those hits too instead of emitting smeared points.
                if hit {
                    let e = 0.01
                    let hp = eye + dir * t
                    let n = Vector3(scene(hp + Vector3(e, 0, 0)) - scene(hp - Vector3(e, 0, 0)),
                                    scene(hp + Vector3(0, e, 0)) - scene(hp - Vector3(0, e, 0)),
                                    scene(hp + Vector3(0, 0, e)) - scene(hp - Vector3(0, 0, e))).normalized
                    if abs(n.dot(dir)) < 0.22 { hit = false }
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

    // The staged set for this figure: the room's bare corner. (The chapter's
    // earlier figures stage a ball and a crate too; a sweep that only arcs in
    // front of a body leaves its far side unobserved, and the rebuilt surface
    // frays just past where the data stops, so the clean sweep here is the
    // whole set. The chapter says why.)
    static func scene(_ p: Vector3) -> Double {
        let floor = p.y
        let back = p.z + 2.4
        let left = p.x + 2.4
        return min(floor, min(back, left))
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
