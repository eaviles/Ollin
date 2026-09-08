import Ollin

/// Newton's basins: a handful of roots placed on the plane, Newton's method run
/// from every pixel, and each pixel colored by the root it lands on. The method
/// is the step every numeric solver takes, z -= p(z) / p'(z), and far from the
/// roots it cannot make up its mind: wherever two basins meet, every other one
/// shows up too, at every scale, so the boundaries are dust where all the
/// colors touch. The roots ride slow orbits here (one of them wanders in and
/// out on a loop of its own), so the basins pour from one arrangement into the
/// next, and `relaxation` scales the step: below 1 the method creeps and the
/// basins fatten, above 1 it overshoots and they spiral and shed islands. A
/// pixel the method never brings home is painted `trapped`, which is what the
/// dark pools are once the dial leaves 1. Everything loops in twelve seconds:
///
/// ```sh
/// swift run Example-Effects-NewtonBasins --export-loop /tmp/newton.gif
/// ```
///
/// Try it: more roots (the palette spreads around them), `shading` at 1 for
/// the contour per step, or `relaxation` held at 1 to see the plain method.
@main
final class NewtonBasins_Example: Sketch {
    private let period = 12.0
    override var loopDuration: Double? { period }

    @Param(2 ... 8, icon: "circle.hexagongrid") var roots = 3
    @Param(0.5 ... 1.8, icon: "figure.walk") var relaxation = 1.0
    @Param(0 ... 1, icon: "circle.lefthalf.filled") var shading = 0.6
    @Param(icon: "smallcircle.filled.circle") var showsRoots = true

    override func draw() {
        let paper = Color(hex: 0x14202B)
        background(paper)
        let lap = loopProgress(over: period)
        let turn = lap * .tau

        // The roots: on a ring that turns once a loop and breathes, with the
        // first one swinging in toward the middle and back out.
        let points = (0 ..< roots).map { i -> Vector2 in
            let a = Double(i) / Double(roots) * .tau + turn * 0.5
            var radius = 0.85 + 0.15 * sin(turn * 2 + Double(i))
            if i == 0 { radius *= 0.55 + 0.45 * cos(turn) }
            return Vector2(cos(a) * radius, sin(a) * radius)
        }
        let field = generate(.newton(roots: points, trapped: paper, shading: shading,
                                     relaxation: relaxation, zoom: 0.9,
                                     iterations: 64, phase: lap))
        drawImage(field.image, 0, 0)

        guard showsRoots else { return }
        // Zoom 0.9 shows 3 / 0.9 units across the shorter side, y up.
        let span = 3.0 / 0.9
        let side = min(width, height)
        noFill()
        stroke(.white)
        strokeWeight(2)
        for p in points {
            drawCircle(width / 2 + p.x / span * side, height / 2 - p.y / span * side, 7)
        }
    }
}
