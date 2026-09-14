import Ollin

/// Two populations on one land, eating each other: a **predator-prey** field
/// (`Sim.predatorPrey`), the Lotka-Volterra idea in the Rosenzweig-MacArthur form.
/// Prey breed toward the land's capacity, predators eat them at a rate that
/// saturates when prey are everywhere, then die off at their own rate, and both
/// wander by diffusion. The field rests at full prey and no predators, so every
/// wave here started as a drawn green mark: an invasion front runs out from it,
/// and in its wake the two populations chase each other around their cycle a
/// little out of step with their neighbors, which is what turns the wake into
/// rotating spirals. Drag to release predators; hold any key while dragging to
/// clear the land. The parameters retune the ecology live: raise the predators'
/// death rate toward their growth rate, or the half-saturation toward the
/// capacity, and the cycle calms into coexistence and the waves die out.
///
/// The raw field is prey in red and predators in green; the gradient map reads
/// that mix as a land map, bare soil to meadow to the predators' orange. See
/// `Simulation/GrayScott` for the two-chemical sibling.
@main
final class PredatorPrey: Sketch {

    /// The prey density, as a share of the capacity, at which a predator eats at
    /// half its top speed. Lower is a more voracious predator and a wilder cycle.
    @Param("Half saturation", 0.1 ... 0.9, icon: "fork.knife", group: "Ecology") var halfSaturation = 0.4
    /// How fast a full predator population grows, in units of the prey's growth.
    @Param("Predator growth", 0.8 ... 4, icon: "arrow.up.right", group: "Ecology") var predatorGrowth = 2.0
    /// How fast predators die off without prey, in the same units.
    @Param("Predator death", 0.2 ... 1.5, icon: "arrow.down.right", group: "Ecology") var predatorDeath = 0.6
    /// Integration steps a frame: the pace of the seasons.
    @Param("Pace", 1 ... 16, icon: "speedometer", group: "Ecology") var pace = 8

    private var land: SimField!

    /// Bare soil where both are gone, meadow where the prey stand alone, the
    /// predators' orange where they have arrived, and pale where both crowd.
    private let map = Ramp(stops: [(0.00, Color(hex: 0x1B1A17)),
                                   (0.21, Color(hex: 0x3E8E4E)),
                                   (0.45, Color(hex: 0xD9A441)),
                                   (0.72, Color(hex: 0xE0522F)),
                                   (1.00, Color(hex: 0xFBEBD0))])

    override func setup() {
        seed(3)
        land = makeSimField(.predatorPrey(), scale: 0.5)
    }

    override func draw() {
        background(.black)
        land.sim = .predatorPrey(halfSaturation: halfSaturation, predatorGrowth: predatorGrowth,
                                 predatorDeath: predatorDeath, steps: pace)
        withField(land) {
            noStroke()
            if frameCount == 1 {
                // A handful of releases: each becomes a front, then spirals.
                fill(Color(red: 0, green: 1, blue: 0))
                for _ in 0 ..< 6 { drawCircle(random(width), random(height), 6) }
            }
            if mouseIsPressed {
                fill(keyIsPressed ? .black : Color(red: 0, green: 1, blue: 0))
                drawCircle(mouseX, mouseY, keyIsPressed ? 80 : 10)
            }
        }
        drawImage(land.filtered(.gradientMap(map)).image, 0, 0)
        drawCaption("predator-prey · prey and predators chasing each other in waves · drag to release predators, hold a key to clear")
    }
}
