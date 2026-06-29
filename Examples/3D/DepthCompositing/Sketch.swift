import Ollin

/// Depth-aware compositing: 2D drawing placed *inside* a 3D scene, occluding and
/// occluded by it.
///
/// By default a 2D draw in a 3D frame lays over everything — fine for a HUD, wrong
/// for something that lives in the scene. `depth(at:)` puts subsequent 2D drawing
/// at the depth of a world point, so it z-tests against the 3D geometry: hidden
/// where the scene is nearer, drawn over where it's in front. `project(_:)` maps a
/// world point to its place on the canvas, and `withBillboard(at:)` does both —
/// move the origin to a world point and set its depth — so you draw a 2D mark in
/// local coordinates and it lands in space with correct occlusion.
///
/// Here a translucent card stands at the world origin while a ring of glowing orbs
/// orbits through it: the orbs in front draw over the card, the orbs behind are
/// hidden by it. The number pins ride the orbs the same way — a pin on the far
/// side of the ring disappears behind the card as it swings around.
@main
final class DepthCompositing: Sketch {
    let orbCount = 14
    let ringRadius = 1.7

    /// A fixed cloud of small offsets, generated once, that turns each orb center
    /// into a glowing ball of splats — shared by every orb so the balls hold still
    /// (only their centers move with time). Built from a deterministic hash so the
    /// render is reproducible (the snapshot test depends on it).
    let blob: [Vector3] = {
        func h(_ n: Int) -> Double {     // a reproducible −1…1 hash
            let x = sin(Double(n) * 12.9898) * 43758.5453
            return (x - floor(x)) * 2 - 1
        }
        return (0..<80).map { i in
            Vector3(h(i * 4), h(i * 4 + 1), h(i * 4 + 2)) * (abs(h(i * 4 + 3)) * 0.16 + 0.04)
        }
    }()

    override func draw() {
        background(Color(hex: 0x070912))

        // Orbit the camera, looking along the ring's plane so orbs pass clearly in
        // front of and behind the card at the center.
        cameraShowcase(.turntable(period: .tau / 0.35), radius: 5.2, elevation: 0.22,
                    fieldOfView: .pi / 3.6)
        // The camera's eye, to seat each pin on the camera-facing surface of its orb
        // rather than buried in it; it tracks the viewer when they take the camera.
        let eye = activeCamera?.eye ?? .zero

        // The ring of orbs (3D point cloud). Each orb is a little cluster of splats
        // so it reads as a glowing ball and occludes solidly.
        var cloud = PointCloud()
        var orbCenters: [Vector3] = []
        for i in 0..<orbCount {
            let a = Double(i) / Double(orbCount) * .tau + time * 0.25
            let center = Vector3(cos(a) * ringRadius, sin(a * 2) * 0.35, sin(a) * ringRadius)
            orbCenters.append(center)
            let hue = Double(i) / Double(orbCount)
            let color = Color(hue: hue, saturation: 0.7, brightness: 1.0)
            for off in blob {
                cloud.add(center + off, color: color, size: 0.05)
            }
        }
        drawPointCloud(cloud)

        // The 2D card, standing at the world origin. `withBillboard(at: .zero)`
        // moves the canvas origin to the origin's screen position and sets the
        // depth to the origin's depth, so everything inside draws in local
        // coordinates and composites against the ring: the near orbs are drawn
        // over it, the far orbs are hidden behind it.
        withBillboard(at: .zero) {
            noStroke()
            fill(Color(white: 0.96, alpha: 0.86))
            drawRect(center: .zero, width: 280, height: 170, cornerRadius: 18)
            fill(Color(hex: 0x070912))
            textAlign(.center, .middle)
            textSize(34)
            drawText("inside the scene", 0, -16)
            textSize(17)
            fill(Color(white: 0.35))
            drawText("2D, depth-tested against the ring", 0, 24)
        }

        // A numbered pin riding each orb, also depth-composited — a pin on the far
        // side of the ring vanishes behind the card as it swings around. This is
        // the per-point form of the same idea (one billboard per world point).
        for (i, center) in orbCenters.enumerated() {
            // Seat the pin just in front of the orb (toward the camera) so it isn't
            // hidden by its own splats, while still living at the orb's depth.
            let toEye = eye - center
            let len = toEye.length
            let anchor = len > 0 ? center + toEye * (0.26 / len) : center
            withBillboard(at: anchor) {
                noStroke()
                fill(.black)
                drawCircle(0, 0, 15)
                fill(.white)
                drawCircle(0, 0, 13)
                fill(.black)
                textAlign(.center, .middle)
                textSize(16)
                drawText("\(i + 1)", 0, 0)
            }
        }

        // A plain top-left HUD, drawn with no depth — it stays over everything, the
        // default for 2D in a 3D frame.
        fill(Color(white: 0.7))
        textAlign(.left, .top)
        textSize(16)
        drawText("depth-aware compositing", 24, 24)
    }
}
