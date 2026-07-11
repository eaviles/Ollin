import Ollin

/// **Turmites**: tiny Turing machines walking a wrapped grid, painting as they go.
/// `Turmite` holds the grid and the ant; each frame steps it a few hundred moves and
/// redraws the painted cells. The preset menu switches personalities: Langton's ant
/// (chaos, then the famous highway around step 10,000), a spiral builder, a chaotic
/// weaver, a framed texture, and a slow Fibonacci spiral. Click to wipe the grid and
/// start the machine over.
@main
final class Turmites: Sketch {

    @Param(icon: "ant", group: "Machine") var preset: Turmite.Preset = .langton
    @Param(1 ... 3000, icon: "speedometer", group: "Machine") var speed = 500

    private let cells = 270   // 4px cells on the default canvas
    private var machine: Turmite!
    private var active: Turmite.Preset = .langton

    override func setup() { restart() }

    override func mousePressed() { restart() }

    private func restart() {
        active = preset
        machine = Turmite(active, columns: cells, rows: cells)
    }

    override func draw() {
        if preset != active { restart() }
        machine.step(speed)

        background(Color(hex: 0x10_0E_14))
        let cell = width / Double(cells)
        noStroke()
        fill(Color(hex: 0xEA_E3_D4))
        for painted in machine.paintedCells {
            drawRect(Double(painted.column) * cell, Double(painted.row) * cell, cell, cell)
        }
        // The walkers, as warm accents big enough to spot.
        fill(Color(hex: 0xFF_7B_4D))
        for ant in machine.antPositions {
            drawCircle((Double(ant.column) + 0.5) * cell, (Double(ant.row) + 0.5) * cell, cell * 1.6)
        }
        drawCaption("turmite · \(active.rawValue) · \(machine.stepCount) steps · click to restart")
    }
}
