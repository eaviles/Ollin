import Ollin

/// A rain-swept pool: the 2D wave equation running as a `.ripples` SimField.
/// Seeded rain dabs soft drops onto the surface (a radial gradient fading to
/// clear, the drop shape that rings cleanly), each bump collapses into
/// expanding rings, and the rings cross, reflect softly off the rim, and die
/// away. The raw state (height + velocity) is shaded into water by `.relight`,
/// reading the height field as a surface. Click or drag to add your own drops.
@main
final class Ripples: Sketch {
    private var pool: SimField!

    @Param(0 ... 12, icon: "cloud.rain") var rain = 5.0
    @Param(0.9 ... 1, icon: "water.waves") var damping = 0.996

    override func setup() {
        pool = simField(.ripples(damping: damping))
    }

    override func draw() {
        background(.black)
        pool.sim = .ripples(damping: damping)

        withField(pool) {
            // Rain: a few seeded drops a second, sized and placed by the
            // sketch's own rng so an export reproduces.
            let perFrame = rain / 60
            if random(0, 1) < perFrame || (perFrame >= 1 && frameCount % 2 == 0) {
                dab(random(60, width - 60), random(60, height - 60),
                    radius: random(6, 22), strength: random(0.25, 0.7))
            }
            if mouseIsPressed {
                dab(mouseX, mouseY, radius: 16, strength: 0.5)
            }
        }

        let water = pool.filtered(.relight(.liquid, angle: -.pi * 0.7, elevation: 0.7,
                                           height: 9, intensity: 1.15,
                                           color: Color(hex: 0x3D6E8F)))
        drawImage(water.image, 0, 0)
    }

    /// One raindrop: a soft dab whose brightness *adds* to the surface height.
    private func dab(_ x: Double, _ y: Double, radius: Double, strength: Double) {
        fill(.radial(center: Vector2(x, y), radius: radius,
                     [Color(white: 1, alpha: strength), Color(white: 1, alpha: 0)]))
        drawCircle(x, y, radius)
    }
}
