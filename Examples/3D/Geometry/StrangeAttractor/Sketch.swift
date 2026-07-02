import Ollin

/// The Lorenz attractor, integrated once and orbited: 150k points along a single
/// chaotic trajectory, colored by how fast the orbit is moving (slow in the
/// quiet centers of the two lobes, fast on the outer sweeps) and lit additively
/// so the dense passes glow.
///
/// `StrangeAttractor.lorenz()` carries the system's velocity field; `orbit`
/// integrates it with fourth-order Runge-Kutta. The path only reads in three
/// dimensions, so it rides the point-cloud path through the camera: build the
/// cloud once in `setup()` (the orbit never changes), then `cameraShowcase` lets
/// you grab and spin it (drag to orbit, scroll to zoom), drifting on its own when
/// you let go.
@main
final class StrangeAttractor3D: Sketch {
    let pointCount = 150_000
    let targetExtent = 4.6        // world size the orbit is fit into

    var cloud = PointCloud()

    override func setup() {
        let attractor = StrangeAttractor.lorenz()
        let raw = attractor.orbit(count: pointCount, settle: 2000)

        // Fit the raw orbit (Lorenz lives around x,y in ±25, z in 0…50) into a
        // tidy box centered on the origin, standing it upright (its tall z axis
        // becomes world up) so the butterfly reads head-on.
        var lo = raw[0], hi = raw[0]
        for p in raw {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        let center = (lo + hi) * 0.5
        let span = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
        let fit = targetExtent / span

        // Color by orbit speed, the magnitude of the velocity field at each point.
        let speeds = raw.map { attractor.derivative($0).length }
        let slow = speeds.min() ?? 0, fast = speeds.max() ?? 1
        let spread = max(fast - slow, 1e-6)

        cloud.points.reserveCapacity(raw.count)
        for (i, p) in raw.enumerated() {
            let c = p - center
            let upright = Vector3(c.x, c.z, c.y) * fit       // z up
            let t = (speeds[i] - slow) / spread              // 0 slow … 1 fast
            let color = Color(hue: 0.62 - t * 0.62, saturation: 0.85, brightness: 0.45 + t * 0.55)
            cloud.add(upright, color: color, size: 0.012)
        }
    }

    override func draw() {
        background(Color(hex: 0x04050A))
        blendMode(.add)          // dense passes of the orbit sum into light
        cameraShowcase(.turntable(period: .tau / 0.25), target: .zero, radius: 5.2,
                       elevation: 0.32, fieldOfView: .pi / 3.4)
        drawPointCloud(cloud)
        drawCaption("Lorenz attractor · drag to orbit · scroll to zoom")
    }
}
