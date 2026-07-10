import Ollin

/// Recursive subdivision, the grid-painting look: the canvas splits across its
/// longer side at a random fraction, the pieces split again, and a coin
/// decides when each panel stops. Most panels stay paper-white; a few take a
/// primary color, and heavy dark rules separate them all. Every few seconds a
/// new seed re-rolls the whole composition.
@main
final class SubdivisionPanels: Sketch {
    override func draw() {
        let roll = frameCount / 200
        seed(roll + 17)

        background(Color(hex: 0xF4EFE6))
        let cells = subdivide(in: bounds.inset(by: .all(60 * scale)),
                              minSize: 80 * scale, maxDepth: 7, chance: 0.72)

        stroke(Color(hex: 0x14110F))
        strokeWeight(10 * scale)
        strokeJoin(.miter)
        let accents: [Color] = [Color(hex: 0xC5283D), Color(hex: 0xF9DC5C), Color(hex: 0x255C99)]
        for cell in cells {
            // Mostly white; deeper (smaller) panels take an accent more often.
            let accentChance = 0.12 + Double(cell.depth) * 0.03
            if random(0, 1) < accentChance {
                fill(randomChoice(accents))
            } else {
                fill(Color(hex: 0xF4EFE6))
            }
            drawRect(cell.frame)
        }
    }
}
