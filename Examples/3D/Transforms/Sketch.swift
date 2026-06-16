import Ollin

/// The 3D transform stack — the spatial sibling of the 2D one.
///
/// In a 3D frame (one with a `camera`), `translate`, `rotateX/Y/Z`, and `scale`
/// build a 4×4 model matrix that moves geometry *inside* the camera, and
/// `withState { }` saves and restores it. That's all you need for the classic
/// orbit-within-an-orbit: a sun spins at the origin, planets orbit the sun, and a
/// moon orbits each planet — every body is the *same* unit point-cloud blob, placed
/// by a different stack of transforms. Nesting `withState` is what lets a moon
/// inherit its planet's orbit and add its own on top.
///
/// World space is right-handed and y-up; rotations are right-handed. Splat sizes
/// are world units, so `scale` grows a body's dots along with it.
@main
final class Transforms3D: Sketch {
    private var sun = PointCloud()
    private var planets: [PointCloud] = []
    private var moon = PointCloud()

    override func setup() {
        seed(7)
        sun = makeBlob(count: 2600, dotSize: 0.05,
                       color: Color(hue: 0.09, saturation: 0.85, brightness: 1.0))
        // Three planets in distinct hues, spread around the color wheel.
        planets = (0..<3).map { i in
            makeBlob(count: 1500, dotSize: 0.06,
                     color: Color(hue: 0.55 + Double(i) * 0.16, saturation: 0.7, brightness: 0.95))
        }
        // The moon rides a tiny scale, so its dots start large to survive the shrink.
        moon = makeBlob(count: 700, dotSize: 0.12, color: Color(white: 0.82))
    }

    override func draw() {
        background(Color(hex: 0x04050A))

        // Orbit the camera slowly around the whole mobile, looking slightly down.
        camera(.orbiting(target: .zero, radius: 8.5,
                         azimuth: time * 0.12, elevation: 0.40,
                         fieldOfView: .pi / 3.2))

        withState {
            rotateY(time * 0.35)                 // the system turns as a whole

            // The sun, a fat blob at the origin.
            withState {
                scale(Vector3(1.05, 1.05, 1.05))
                drawPointCloud(sun)
            }

            // Each planet on its own orbit, with a moon orbiting it in turn.
            for (i, planet) in planets.enumerated() {
                let orbit = 2.4 + Double(i) * 1.55    // orbital radius
                let speed = 0.9 - Double(i) * 0.22    // inner planets are faster
                withState {
                    rotateY(time * speed + Double(i) * 2.1)   // walk around the orbit
                    translate(orbit, 0, 0)                    // step out to it

                    // The planet body, sized down from the sun.
                    let r = 0.62 - Double(i) * 0.07
                    withState {
                        scale(Vector3(r, r, r))
                        drawPointCloud(planet)
                    }

                    // The moon: a second orbit nested inside the planet's frame, so
                    // it inherits the planet's position and adds its own circle.
                    withState {
                        rotateY(time * 2.2 + Double(i))
                        translate(0.85 + r, 0, 0)
                        scale(Vector3(0.3, 0.3, 0.3))
                        drawPointCloud(moon)
                    }
                }
            }
        }

        drawCaption("3D transform stack — orbits within orbits, one blob placed many ways")
    }

    /// A fuzzy unit sphere of points (radius ≈ 1, centered at the origin), so a
    /// `scale` sizes it and a `translate` places it. Points sit on the sphere's
    /// shell with a little jitter, shaded a touch by height for roundness.
    /// `dotSize` is the splat diameter at unit scale — a body drawn at a small
    /// scale needs a larger `dotSize`, since the transform shrinks its dots too.
    private func makeBlob(count: Int, dotSize: Double, color: Color) -> PointCloud {
        var cloud = PointCloud()
        cloud.points.reserveCapacity(count)
        for _ in 0..<count {
            // A uniform direction on the unit sphere (normalized Gaussian triple),
            // pushed to the shell with a small radial jitter.
            let dir = Vector3(randomGaussian(), randomGaussian(), randomGaussian()).normalized
            let p = dir * (0.92 + random(0.16))
            let shade = 0.7 + (p.y * 0.5 + 0.5) * 0.5    // lighter toward the top
            let c = Color(red: color.red * shade, green: color.green * shade,
                          blue: color.blue * shade, alpha: 1)
            cloud.add(p, color: c, size: dotSize)
        }
        return cloud
    }
}
