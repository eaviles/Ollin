import Ollin

/// Particle Life: a handful of particle kinds, one attraction-or-repulsion number for
/// every ordered pair of them, and from that alone come membranes, cells, chasers, and
/// worms. Tens of thousands of particles interact in real time because the `SpatialHash`
/// finds each one's neighbors on the GPU instead of checking all pairs.
///
/// Every particle feels a short-range shove away from whoever is too close, then, a
/// little further out, an attraction or repulsion set by the matrix entry for the two
/// kinds. The matrix is random and usually asymmetric (red chases blue, blue flees red),
/// which is what makes the whole thing come alive rather than settle. Click to roll a
/// new matrix; each `variation` reshuffles the whole world.
@main
final class ParticleLife_Example: Sketch {
    var life: ParticleLife!

    // Live knobs: drag these in the OllinLive / gallery inspector to feel how the
    // interaction changes the emergent behavior.
    @Param(0.05 ... 0.6, icon: "circle.circle") var beta = 0.3
    @Param(1 ... 16, icon: "bolt") var force = 7.0
    @Param(0.01 ... 0.15, icon: "drop") var friction = 0.045

    override func setup() {
        life = particleLife(count: 24_000, kinds: 6, radius: 46)
    }

    override func draw() {
        life.beta = beta
        life.forceFactor = force
        life.frictionHalfLife = friction

        background(Color(white: 0.04))
        blendMode(.add)
        updateParticleLife(life)
        drawParticles(life)

        blendMode(.normal)
        drawCaption("Particle Life · 24,000 particles, 6 kinds · click to reshuffle the rules")
    }

    override func mousePressed() {
        life.randomizeMatrix(seed: UInt64(frameCount) &* 2654435761)
    }
}
