// figure: frame=900
//
// Guide diagram (Chapter 18): multi-scale Turing patterns. Two fields side by
// side from the same noise seed. Left runs a single scale, which settles into
// one wavelength everywhere, the stripes of a zebra. Right runs the five-rung
// ladder, where each pixel picks the scale that disagrees least with itself, so
// coarse lobes and fine detail share one picture. Both are shaded as relief,
// which is the look the algorithm is known for.
import Ollin

final class TuringScales: Sketch {
    override var canvasSize: CanvasSize { .size(720, 380) }

    var single: SimField!
    var many: SimField!

    override func setup() {
        // One rung: a plain Turing rule, one activator radius against one inhibitor.
        single = simField(.multiScaleTuring(scales: [
            TuringScale(activatorRadius: 4, inhibitorRadius: 8, amount: 0.02)
        ], seed: 12), width: 350, height: 350)
        // Five rungs doubling from 2 to 32, all pushing equally hard.
        many = simField(.multiScaleTuring(scales: .ladder, seed: 12),
                        width: 350, height: 350)
    }

    override func draw() {
        background(.white)
        // Nothing is drawn into either field: they start from noise and organize
        // themselves, so reading them is what keeps them running.
        drawImage(single.filtered(.relight(height: 0.35)).image, 5, 15)
        drawImage(many.filtered(.relight(height: 0.35)).image, 365, 15)

        fill(.black)
        noStroke()
        textFont(.system)
        textSize(13)
        textAlign(.center)
        drawText("one scale", 180, 378)
        drawText("five scales", 540, 378)
    }
}
