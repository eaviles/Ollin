import Ollin

/// Silverman's **Brian's Brain**, the three-state automaton that reads as pure
/// electricity: every cell is ready, firing, or resting. A ready cell fires when
/// exactly two of its eight neighbors are firing, a firing cell spends the next
/// step resting (and cannot be re-lit), and a resting cell returns to ready.
/// Almost any random soup explodes into permanent traffic, gliders racing along
/// the diagonals and orthogonals trailed by their afterglow, though a *solid* blob
/// dies at once (every interior cell rests together, and a flat edge shows three
/// neighbors where a birth needs exactly two), so the brush here sprinkles loose
/// cells rather than painting a disc. The ramp keeps the classic reading (black
/// ground, cool afterglow, white fire). Drag to sprinkle more; hold a key and
/// drag to wipe a region clear.
@main
final class BriansBrain: Sketch {

    private var field: SimField!

    /// Ready is the dark ground, resting the cool afterglow, firing the white spark.
    private let glow = Ramp(stops: [(0.0, Color(hex: 0x05070C)),
                                    (0.5, Color(hex: 0x3A6BD8)),
                                    (1.0, .white)])

    override func setup() {
        field = simField(.briansBrain(), scale: 0.15)
    }

    override func draw() {
        background(.black)

        withField(field) {
            noStroke()
            if frameCount == 1 {           // the classic start: soup everywhere
                fill(.white)
                for _ in 0 ..< 6500 {
                    drawCircle(random(width), random(height), 3.4)
                }
            }
            if mouseIsPressed {
                if keyIsPressed {
                    fill(.black)
                    drawCircle(mouseX, mouseY, 80)
                } else {
                    sprinkle(mouseX, mouseY, radius: 60)
                }
            }
        }
        drawImage(field.filtered(.gradientMap(glow)).image, 0, 0)
        drawCaption("Brian's Brain · fire on exactly two · drag to sprinkle, hold a key to clear")
    }

    /// A pinch of random soup: loose single cells at the density that boils. One
    /// dot is one field cell, so the dot radius follows the field's scale.
    private func sprinkle(_ x: Double, _ y: Double, radius: Double = 150) {
        fill(.white)
        for _ in 0 ..< Int(radius * radius * 0.018) {   // constant soup density
            let angle = random(.pi * 2)
            let r = radius * random().squareRoot()
            drawCircle(x + cos(angle) * r, y + sin(angle) * r, 3.4)
        }
    }
}
