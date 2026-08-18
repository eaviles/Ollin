import Ollin

/// An ant colony solving a tour, watched from above: the cities are a seeded
/// scatter, and every frame the whole colony walks once and re-lays its
/// pheromone. The web of trails starts as a faint haze over every pair,
/// then condenses onto a short route as good edges reinforce and the rest
/// evaporate. The best tour so far rides on top in bright ink.
@main
final class AntColonyTour: Sketch {
    private var colony: AntColony?

    override func draw() {
        let colony = self.colony ?? {
            seed(12)
            let cities = poissonDisk(in: bounds.inset(by: .all(90 * scale)),
                                     radius: 130)
            let made = AntColony(cities: cities, elitism: 2, seed: 12)
            self.colony = made
            return made
        }()

        colony.step()

        background(Color(hex: 0x14100C))
        strokeCap(.round)

        // The pheromone web: every pair the colony still believes in.
        for trail in colony.trails {
            stroke(Color(red: 1.0, green: 0.72, blue: 0.35,
                         alpha: 0.04 + trail.strength * 0.5))
            strokeWeight((0.5 + trail.strength * 3) * scale)
            drawLine(trail.a, trail.b)
        }

        // The answer so far.
        stroke(Color(hex: 0xF6EFE2))
        strokeWeight(2.5 * scale)
        noFill()
        drawPolyline(colony.bestTourPoints, closed: true)

        noStroke()
        fill(Color(hex: 0xE4572E))
        for city in colony.cities {
            drawCircle(city.x, city.y, 7 * scale)
        }
    }
}
