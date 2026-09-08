// A homage after John Whitney (1917-1995), made for learning. Not a reproduction
// of a specific film, and not affiliated with or endorsed by the artist or his
// estate. Written from his own statement of the rule in *Digital Harmony: On the
// Complementarity of Music and Visual Art* (Byte Books, 1980), where he sets a
// first element moving at a given rate, the next at two times that rate, the
// third at three, and so on, and where the example worked in the book puts those
// elements on a series of increasingly wider concentric circles. The reading of
// that construction was cross-checked against Jim Bumgardner's account of it in
// "The Whitney Music Box" (Bridges 2007, jbum.com/papers/whitney_paper.pdf).
// No code of anyone's was ported; the film that demonstrates the principle is
// *Permutations* (1968).
import Ollin

/// Whitney's rule: every point turns at a whole-number multiple of one rate, so
/// nothing wanders and the figure keeps coming back. Point 1 makes one turn in a
/// cycle, point 2 makes two, point 60 makes sixty. They leave together, fan into
/// a spiral, and gather again into two arms at half a cycle, three at a third, and
/// so on down the fractions. He called those gatherings harmonic resonance, and
/// held that they are to seeing what a chord is to hearing.
@main
final class Permutations: Sketch {

    /// How many points turn. Each one is a whole-number multiple of the first.
    @Param(6...600) var points = 150
    /// Seconds for the slowest point to come all the way around, which is also
    /// the period of the whole figure.
    @Param(6...120) var cycle = 30.0
    /// The whole number between one point's rate and the next.
    @Param(1...6) var step = 1
    /// How big the marks are.
    @Param(1...14) var dotSize = 5.0

    let palette = CosinePalette.neon

    override func draw() {
        background(Color(white: 0.04))
        noStroke()

        let reach = min(width, height) * 0.46
        let turn = time / cycle

        for index in 1...points {
            let fraction = Double(index) / Double(points)
            // The rule: rate is the index, times the whole-number step.
            let angle = .tau * Double(index * step) * turn - .pi / 2
            let at = center + Vector2(cos(angle), sin(angle)) * (reach * fraction)

            fill(palette.color(at: fraction))
            drawCircle(center: at, radius: dotSize * scale)
        }
    }
}
