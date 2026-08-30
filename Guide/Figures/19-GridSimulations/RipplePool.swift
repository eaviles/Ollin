// figure: frame=126
//
// Guide diagram (Chapter 19): the ripples field. Three drops added to the
// surface at fixed frames, their rings crossing and reflecting off the rim
// by the time this frame is captured. The raw state is height and velocity,
// so it is shaded into water by reading the height as a surface.
import Ollin

final class RipplePool: Sketch {
    override var canvasSize: CanvasSize { .square(720) }

    var pool: SimField!

    override func setup() {
        pool = makeSimField(.ripples(damping: 0.995))
    }

    override func draw() {
        background(.black)

        withField(pool) {
            if frameCount == 8 { dab(250, 260, radius: 22, strength: 0.85) }
            if frameCount == 46 { dab(470, 350, radius: 18, strength: 0.75) }
            if frameCount == 84 { dab(330, 505, radius: 15, strength: 0.65) }
        }

        let water = pool.filtered(.relight(.liquid, angle: -.pi * 0.7,
                                           elevation: 0.7, height: 9,
                                           intensity: 1.15,
                                           color: Color(hex: 0x3D6E8F)))
        drawImage(water.image, 0, 0)
    }

    /// One drop: a soft dab whose brightness adds to the surface height. The
    /// gradient matters, since a hard-edged disc rings at every frequency.
    func dab(_ x: Double, _ y: Double, radius: Double, strength: Double) {
        fill(.radial(center: Vector2(x, y), radius: radius,
                     [Color(white: 1, alpha: strength), Color(white: 1, alpha: 0)]))
        drawCircle(x, y, radius)
    }
}
