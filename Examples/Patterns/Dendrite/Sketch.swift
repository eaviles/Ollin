import Ollin

/// Diffusion-limited aggregation: random walkers drift in from the rim and
/// freeze where they first touch the cluster, so branching dendrites grow
/// from a single seed, the way frost creeps over glass. Tips catch walkers
/// before hollows ever see one, which is why the arms stay wispy and the
/// gaps stay open. Each particle is tinted by its arrival time, so the
/// growth history reads as rings of color.
@main
final class Dendrite: Sketch {
    private var cluster: DiffusionLimitedAggregation?
    private let ramp = Ramp([
        Color(hex: 0xF2EFE8), Color(hex: 0x9AD9CE),
        Color(hex: 0x5B8FB9), Color(hex: 0x8A5BB9),
    ])

    override func draw() {
        if cluster == nil {
            cluster = DiffusionLimitedAggregation(
                seeds: [center], particleRadius: 3.4 * scale,
                bounds: bounds, maxParticles: 5200, seed: 11)
        }
        guard let cluster else { return }
        cluster.step(14)

        background(Color(hex: 0x0E1016))
        noStroke()
        let count = Double(cluster.count)
        for (i, particle) in cluster.particles.enumerated() {
            fill(ramp.color(at: Double(i) / count))
            drawCircle(center: particle.position, radius: 3.4 * scale)
        }
    }
}
