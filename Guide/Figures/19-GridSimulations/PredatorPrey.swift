// figure: frame=600
//
// Guide diagram (Chapter 19): a predator-prey field twice, from the same
// releases. Left, sixty frames after predators were dropped on full prey: an
// invasion front running out from each release. Right, six hundred frames
// after: the fronts have met and the wake behind them has broken into curling
// wave fragments, the spiral arms of the model's spatial chaos. Two fields, seeded the same way at different ages, since a field
// steps every frame it is read.
import Ollin

final class PredatorPrey: Sketch {
    override var canvasSize: CanvasSize { .size(1000, 500) }

    var young: SimField?
    var old: SimField?
    var releases: [Vector2] = []

    /// Bare soil where both are gone, meadow where the prey stand alone, the
    /// predators' orange where they have arrived, pale where both crowd.
    let map = Ramp(stops: [(0.00, Color(hex: 0x1B1A17)),
                           (0.21, Color(hex: 0x3E8E4E)),
                           (0.45, Color(hex: 0xD9A441)),
                           (0.72, Color(hex: 0xE0522F)),
                           (1.00, Color(hex: 0xFBEBD0))])

    override func setup() {
        seed(5)
        releases = (0 ..< 5).map { _ in Vector2(random(40, 460), random(40, 460)) }
    }

    override func draw() {
        background(Color(hex: 0x1B1A17))
        if young == nil {
            young = makeSimField(.predatorPrey(), width: 500, height: 500)
            old = makeSimField(.predatorPrey(), width: 500, height: 500)
        }
        guard let young, let old else { return }

        // The old field is released on frame 1, the young one 540 frames later,
        // so at the figure's frame they are 600 and 60 frames past their releases.
        withField(old) { if frameCount == 1 { release() } }
        withField(young) { if frameCount == 541 { release() } }

        drawImage(young.filtered(.gradientMap(map)).image, 0, 0)
        drawImage(old.filtered(.gradientMap(map)).image, 500, 0)
    }

    func release() {
        noStroke()
        fill(Color(red: 0, green: 1, blue: 0))
        for r in releases { drawCircle(r.x, r.y, 5) }
    }
}
