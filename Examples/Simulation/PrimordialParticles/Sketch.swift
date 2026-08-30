import Ollin

/// A Primordial Particle System (Schmickl, Stefanec & Crailsheim, 2016): one turning
/// rule, and cells that grow, divide, and die emerge from it. Every step each particle
/// counts its neighbors, sees how many are to its left versus its right, turns a fixed
/// amount plus a crowd-proportional amount toward the busier side, and steps forward.
/// That is the entire law, run on the GPU over the `SpatialHash` neighbor search.
///
/// Watch the coloring: particles are tinted by how crowded they are, so the dense walls
/// of a forming cell read magenta and yellow while free wanderers stay green and blue.
/// The count is picked for the paper's cell-forming density; each `variation` reseeds.
@main
final class PrimordialParticles_Example: Sketch {
    var pps: PPS!

    override func setup() {
        let radius = 22.0
        let count = PPS.suggestedCount(for: radius, in: bounds)
        pps = makePrimordialParticles(count: count, radius: radius)
    }

    override func draw() {
        background(Color(white: 0.06))
        updatePrimordialParticles(pps)
        drawParticles(pps)

        drawCaption("Primordial Particle System · \(pps.count) particles, one turning rule")
    }
}
