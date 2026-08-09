import Ollin

/// Particle Lenia: no force law at all, just an energy field and particles walking
/// downhill on it. Each one adds up a ring-shaped kernel over its neighbors to see how
/// crowded it is, a growth function scores that crowding, a repulsion term stops anyone
/// standing on anyone, and the particle moves whichever way the total improves.
///
/// From those three lines come membranes, cells that hold their shape, rotors, and
/// things that split in two. The knobs are the whole model: `muK` and `sigmaK` are the
/// ring a particle reaches with, `muG` and `sigmaG` the crowding it prefers, and `cRep`
/// how hard it refuses to be crowded. Colour is that crowding measured against what the
/// rule wants, so an interior, a membrane, and a particle out on its own look different.
@main
final class ParticleLenia_Example: Sketch {
    var lenia: ParticleLenia!

    // Live knobs: drag these to feel the model change character. Small moves in muG or
    // sigmaG are the difference between a blob, a ring, and a thing that crawls.
    @Param(2 ... 7, icon: "circle.dashed") var ringRadius = 4.0
    @Param(0.3 ... 1.6, icon: "circle.dotted") var ringWidth = 1.0
    @Param(0.2 ... 1.4, icon: "target") var prefersCrowding = 0.6
    @Param(0.05 ... 0.5, icon: "scope") var fussiness = 0.15
    @Param(0.3 ... 2.5, icon: "arrow.left.and.right") var repulsion = 1.0
    @Param(0.2 ... 4.0, icon: "gauge") var pace = 1.0

    override func setup() {
        lenia = particleLenia(count: 6000, spacing: 8)
    }

    override func draw() {
        lenia.muK = ringRadius
        lenia.sigmaK = ringWidth
        lenia.muG = prefersCrowding
        lenia.sigmaG = fussiness
        lenia.cRep = repulsion
        lenia.speed = pace

        background(Color(white: 0.03))
        blendMode(.add)
        updateParticleLenia(lenia)
        drawParticles(lenia)

        blendMode(.normal)
        drawCaption("Particle Lenia · 6,000 particles walking downhill on one energy field")
    }
}
