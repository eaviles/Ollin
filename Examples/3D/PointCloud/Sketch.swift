import Ollin

/// A 3D point cloud, orbited — Ollin's first 3D sketch.
///
/// Setting a `camera` is what puts a frame into 3D: the renderer adds a depth
/// buffer and projects every point through the camera as a camera-facing disc,
/// sized in world units so perspective shrinks the far ones and the near ripples
/// occlude the far ones (that's the depth test at work). Nothing is tessellated —
/// each point is one instanced splat, so tens of thousands are cheap.
///
/// The cloud here is a rippling heightfield, rebuilt every frame and colored by
/// height. World space is right-handed and y-up, a different convention from the
/// 2D canvas — 3D geometry rides the camera, not the transform stack.
@main
final class PointCloud3D: Sketch {
    let n = 110               // grid resolution: n×n points
    let span = 3.2            // world extent of the field

    override func draw() {
        background(Color(hex: 0x05060A))

        // Orbit the camera slowly around the field, looking slightly down.
        cameraShowcase(.turntable(period: .tau / 0.3), target: Vector3(0, -0.1, 0), radius: 5.4,
                    elevation: 0.5, fieldOfView: .pi / 3.4)

        var cloud = PointCloud()
        cloud.points.reserveCapacity(n * n)
        let step = span / Double(n - 1)
        for i in 0..<n {
            let x = -span / 2 + Double(i) * step
            for j in 0..<n {
                let z = -span / 2 + Double(j) * step
                let r = (x * x + z * z).squareRoot()
                // A radial ripple spreading from the center, plus a rolling swell.
                let h = sin(r * 3.0 - time * 1.6) * 0.34 * exp(-r * 0.35)
                      + sin(x * 1.5 + time) * cos(z * 1.5 - time) * 0.12
                let t = max(0, min(1, h + 0.5))   // height -> 0…1
                let color = Color(hue: 0.62 - t * 0.52, saturation: 0.85,
                                  brightness: 0.42 + t * 0.58)
                cloud.add(Vector3(x, h, z), color: color, size: 0.045)
            }
        }
        drawPointCloud(cloud)
    }
}
