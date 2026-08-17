import Ollin

/// Griffeath's **cyclic cellular automaton**: every cell wears one of `states`
/// colors arranged in a circle, and a cell advances to the next color the moment
/// enough neighbours already wear it, so each color eats the one before it and is
/// eaten by the one after. From pure noise the field self-organizes through the
/// famous four acts, colored static, growing droplets, the first spiral defects,
/// and finally a field of turning spiral cores that own everything. A cyclic hue
/// ramp closes the color wheel so the top state hands off to state zero without a
/// seam. Drag to stamp a disc of one color and watch the spirals eat the wound;
/// raise `threshold` (with corners on) to trade spirals for churning block
/// turbulence.
@main
final class CyclicAutomaton: Sketch {

    @Param(2 ... 24, icon: "circle.grid.3x3", group: "Rule") var states = 14
    @Param(1 ... 4, icon: "chart.bar.fill", group: "Rule") var threshold = 1
    /// Count the corner neighbours too (the eight-cell block instead of the four).
    @Param(icon: "square.grid.3x3", group: "Rule") var corners = false

    private var field: SimField!

    /// The state ramp, closed into a wheel: the last stop repeats the first hue so
    /// the top state advancing to zero reads as one more step, not a cliff.
    private let wheel = Ramp(stops: (0 ... 6).map {
        (position: Double($0) / 6,
         color: Color(hue: Double($0) / 6, saturation: 0.72, brightness: 0.95))
    })

    override func setup() {
        field = simField(.cyclic(seed: Double(variation)), scale: 0.25)
    }

    override func draw() {
        background(.black)
        // Retuning the rule live keeps the evolved field and reshapes it from here on.
        field.sim = .cyclic(states: states, threshold: threshold,
                            neighborhood: corners ? .moore : .vonNeumann,
                            seed: Double(variation))

        withField(field) {
            noStroke()
            if mouseIsPressed {
                fill(.white)   // stamps the top state; the wheel spins it back in
                drawCircle(mouseX, mouseY, 60)
            }
        }
        drawImage(field.filtered(.gradientMap(wheel)).image, 0, 0)
        drawCaption("Cyclic automaton · each color eats the one before it · drag to stamp")
    }
}
