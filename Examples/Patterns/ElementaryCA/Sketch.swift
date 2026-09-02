import Ollin

/// One-dimensional cellular automata drawn the classic way: each generation is a row,
/// time runs down the canvas. The **elementary** family (`elementaryCA`) is the 256
/// two-color rules; the **totalistic** family (`totalisticCA`) reads the neighborhood
/// *sum* over three colors, where richer textures live. Step the rule parameter and watch
/// one number flip the picture between order, fractals, and chaos: 30 boils, 90 is the
/// Sierpinski triangle, 110 grows machinery.
///
/// The whole field recomputes every frame (it is tiny), revealing a few rows per frame
/// so the rule appears to run. Rules land mid-reveal when switched, which is the point:
/// scrub and compare.
@main
final class ElementaryCA: Sketch {

    enum Family: String, CaseIterable, ParamOption { case elementary, totalistic }

    @Param(style: .segmented, icon: "square.stack.3d.up", group: "Rule") var family: Family = .elementary
    @Param(0 ... 255, icon: "number", group: "Rule") var rule = 30
    @Param(0 ... 2186, icon: "number.square", group: "Rule") var code = 777

    private let columns = 181   // odd, so the single seed sits dead center

    override func draw() {
        background(Color(hex: 0x0E_12_16))
        let margin = width * 0.05
        let cell = (width - 2 * margin) / Double(columns)
        let generations = Int((height - 2 * margin) / cell)
        let visible = min(generations, 1 + frameCount * 3)
        let inks: [Color] = [Color(hex: 0xF2_E9_D8), Color(hex: 0xE8_9A_3C), Color(hex: 0x5F_A8_A0)]

        // Recompute the field, then draw one square per live cell, newest rows last.
        let field: [[Int]]
        switch family {
        case .elementary:
            field = elementaryCA(rule: rule, width: columns, generations: generations)
                .map { $0.map { $0 ? 1 : 0 } }
        case .totalistic:
            field = totalisticCA(code: code, colors: 3, width: columns, generations: generations)
        }
        noStroke()
        for r in 0 ..< visible {
            for c in 0 ..< columns where field[r][c] > 0 {
                fill(inks[(field[r][c] - 1) % inks.count])
                drawRect(margin + Double(c) * cell, margin + Double(r) * cell,
                         cell * 0.9, cell * 0.9)
            }
        }
        drawCaption(family == .elementary ? "elementary CA · rule \(rule)"
                                          : "totalistic CA · 3 colors · code \(code)")
    }
}
