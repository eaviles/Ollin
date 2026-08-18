import Ollin

/// A Lichtenberg figure growing live: the dielectric breakdown model solves
/// the electric field around the discharge every step and grows where the
/// field is strongest, raised to the `eta` that makes lightning sparse and
/// directed. Watch it feel its way outward and arc to the rim.
///
/// The channels draw with pipe-model widths, so the main channel thickens
/// and brightens toward the seed while the youngest tips stay hair-fine. Two
/// passes make the glow: a wide violet halo added underneath, the hot core
/// over it. Seeded, so the same figure grows every run.
@main
final class Lichtenberg: Sketch {
    private var bolt: DielectricBreakdown?

    override func draw() {
        let bolt = self.bolt ?? {
            let made = DielectricBreakdown(seeds: [bounds.center], in: bounds,
                                           resolution: 150, eta: 1.9,
                                           maxSites: 6000, seed: 3)
            self.bolt = made
            return made
        }()

        bolt.step(10)

        background(Color(hex: 0x0A0A12))
        let widths = bolt.thicknesses(tipWidth: 1.1, exponent: 2.0)
        let halo = Color(red: 0.55, green: 0.42, blue: 1.0, alpha: 0.22)
        let core = Color(hex: 0xF3EFFF)

        blendMode(.add)
        stroke(halo)
        strokeCap(.round)
        for (i, site) in bolt.sites.enumerated() {
            guard let parent = site.parent else { continue }
            strokeWeight(widths[i] * 4 * scale)
            drawLine(bolt.sites[parent].position, site.position)
        }

        blendMode(.normal)
        stroke(core)
        for (i, site) in bolt.sites.enumerated() {
            guard let parent = site.parent else { continue }
            strokeWeight(widths[i] * scale)
            drawLine(bolt.sites[parent].position, site.position)
        }
    }
}
