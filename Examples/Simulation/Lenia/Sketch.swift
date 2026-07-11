import Ollin

/// **Lenia**, the continuous Game of Life, on the GPU through the effects substrate.
/// A `SimField` running `.lenia()` holds a smooth mass field; every frame the renderer
/// convolves it with a soft ring kernel and grows or starves each texel by how close
/// its neighborhood mass sits to the growth center. Blobs pulse, split, orbit, and
/// swim. The field seeds itself once from the sketch's `variation`; drag to pour in
/// more mass, hold any key while dragging to erase, and tune the growth rule live:
/// small moves of either knob change the ecosystem.
@main
final class Lenia_Example: Sketch {

    @Param(0.05 ... 0.3, icon: "target", group: "Growth") var growthCenter = 0.15
    @Param(0.005 ... 0.05, icon: "slider.horizontal.below.rectangle", group: "Growth") var growthWidth = 0.015

    private var field: SimField!
    private var seeded = false

    override func setup() {
        field = simField(.lenia(), scale: 0.5)
    }

    override func draw() {
        background(.black)
        // The knobs retune the rule live; the field's evolved state carries on.
        field.sim = .lenia(growthCenter: growthCenter, growthWidth: growthWidth)

        withField(field) {
            noStroke()
            if !seeded {   // a dense primordial soup, reproducible per variation
                seeded = true
                for _ in 0 ..< 350 {
                    fill(Color(white: 1, alpha: random(0.2, 0.8)))
                    drawCircle(random(width), random(height), random(15, 70))
                }
            }
            if mouseIsPressed {
                fill(keyIsPressed ? .black : Color(white: 1, alpha: 0.85))
                drawCircle(mouseX, mouseY, 42)
            }
        }
        drawImage(field.filtered(.gradientMap(.magma)).image, 0, 0)
        drawCaption("Lenia · a continuous cellular automaton · drag to add mass, hold a key to erase")
    }
}
