import Ollin

/// The Gerhardt-Schuster **hodgepodge machine**, the automaton built to mimic an
/// oscillating chemical reaction: its curling wavefronts are dead ringers for the
/// Belousov-Zhabotinsky reaction in a dish. Cells run from healthy through degrees
/// of infection to ill and back to healthy at once, catching from their neighbors
/// on the way up, and from a random start the field churns through noise into
/// waves and finally locked spiral cores shedding rings. `speed` is the constant
/// the original authors called *g*, how much sicker an infected cell gets each
/// step: low and the disease dies out, high and the field locks into the spiral
/// regime. Drag to stamp infection and watch the waves close over the wound; hold
/// a key and drag to heal.
@main
final class Hodgepodge: Sketch {

    /// The speed of infection (the rule's constant g), the behavior dial.
    @Param(1 ... 60, icon: "speedometer", group: "Rule") var speed = 25

    private var field: SimField!

    override func setup() {
        field = makeSimField(.hodgepodge(seed: Double(variation)), scale: 0.25)
    }

    override func draw() {
        background(.black)
        field.sim = .hodgepodge(infectionRate: speed, seed: Double(variation))

        withField(field) {
            noStroke()
            if mouseIsPressed {
                fill(keyIsPressed ? .black : Color(white: 0.6))
                drawCircle(mouseX, mouseY, 60)
            }
        }
        drawImage(field.filtered(.gradientMap(.turbo)).image, 0, 0)
        drawCaption("Hodgepodge machine · infection chasing recovery · drag to infect, hold a key to heal")
    }
}
