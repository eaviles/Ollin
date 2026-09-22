import Foundation
import Ollin

/// Fireflies falling into step: four hundred **Kuramoto oscillators**, each a
/// firefly flashing at its own natural pace, each pulled toward the phase of the
/// crowd. Below the critical coupling the meadow twinkles at random; above it a
/// locked group forms and grows until the whole meadow flashes as one. The wheel
/// in the corner is the crowd's phases on a circle with the order parameter drawn
/// from its center: the arrow's length is the coherence r (0 scattered, 1 locked)
/// and its direction the mean phase. `Coupling` is the pull, and the caption
/// names the critical value for the current `Spread`. The crowd is remade when
/// the spread changes, since the natural frequencies are drawn at birth.
///
/// `Field` moves the same fireflies onto a **honeycomb**, where each listens only
/// to the cells within `Listens to` rings of its own instead of to the whole
/// crowd. Now the crowd has a geography: patches fall into step and drift apart,
/// waves of agreement cross the field, and with a `Lag` the locked patterns
/// travel. Each cell's hue is its phase and its saturation is the local order
/// parameter, so a patch in step is vivid, the seam between two patches out of
/// step is gray, and the moment two patches merge is the moment the gray line
/// between them goes.
@main
final class Fireflies: Sketch {

    enum Field: CaseIterable, ParamOption {
        case meadow, honeycomb
    }

    /// The meadow couples every firefly to the whole crowd; the honeycomb couples
    /// each to the cells beside it.
    @Param("Field", icon: "hexagon") var field = Field.meadow
    /// How hard the crowd pulls on each firefly's phase (K, per second).
    @Param("Coupling", 0 ... 4, icon: "link") var coupling = 2.0
    /// The standard deviation of the natural frequencies, in radians per second;
    /// 0 makes every firefly the same, and a wide spread needs a stronger pull.
    @Param("Spread", 0 ... 1.5, icon: "waveform.path") var spread = 0.5
    /// Rings of cells a honeycomb firefly listens to.
    @Param("Listens to", 1 ... 3, icon: "circle.hexagongrid") var listens = 1
    /// A lag in the pull, which on the honeycomb makes a locked pattern travel.
    @Param("Lag", -1 ... 1, icon: "arrow.right.to.line") var lag = 0.0

    private var sync: Kuramoto!
    private var spots: [Vector2] = []
    private var grid: HexGrid!
    private var made: (spread: Double, field: Field)?
    private let count = 400
    private let columns = 26
    private let rows = 22
    private let glow = Color(hex: 0xE9FF7C)

    override func setup() {
        $listens.show(when: $field) { $0 == .honeycomb }
        $lag.show(when: $field) { $0 == .honeycomb }
        remake()
    }

    override func draw() {
        if made?.spread != spread || made?.field != field { remake() }
        sync.coupling = coupling
        sync.range = field == .honeycomb ? listens : 0
        sync.lag = field == .honeycomb ? lag : 0
        sync.advance()

        background(Color(hex: 0x06100E))
        noStroke()
        switch field {
        case .meadow: drawMeadow()
        case .honeycomb: drawHoneycomb()
        }
        drawWheel()
        drawCaption(String(format: "Kuramoto · r = %.2f · coupling %.1f, critical %.2f · drag the sliders",
                           sync.coherence, coupling, sync.criticalCoupling))
    }

    /// A fresh crowd at the current spread, on the field asked for. The run's
    /// variation places the meadow, kept clear of the wheel's corner; the crowd
    /// itself keeps one seed, so its flashes fall on the same frames in every run.
    private func remake() {
        randomSeed(variation)
        let wheel = Vector2(width - 170, height - 190)
        spots = []
        while spots.count < count {
            let spot = Vector2(random(40, width - 40), random(40, height - 120))
            if spot.distance(to: wheel) > 150 { spots.append(spot) }
        }
        switch field {
        case .meadow:
            sync = Kuramoto(count: count, coupling: coupling, frequency: 3, spread: spread, seed: 7)
        case .honeycomb:
            grid = hexGrid(columns: columns, rows: rows,
                           padding: Insets(top: 36, right: 36, bottom: 330, left: 36), gutter: 2)
            sync = Kuramoto(columns: columns, rows: rows, layout: .hex, coupling: coupling,
                            frequency: 3, spread: spread, lag: lag, range: listens, seed: 7)
        }
        made = (spread, field)
    }

    /// Every firefly a flash rather than a sine: the glow rises sharply once a turn.
    private func drawMeadow() {
        for (i, phase) in sync.phases.enumerated() {
            let lit = pow((1 + cos(phase)) / 2, 4)
            fill(glow.withAlpha(lit * 0.22))
            drawCircle(center: spots[i], radius: 16)
            fill(glow.withAlpha(0.06 + lit * 0.94))
            drawCircle(center: spots[i], radius: 3.5)
        }
    }

    /// Every cell painted by its phase, as vivid as its neighborhood agrees: the
    /// hue is the phase, the saturation the local order parameter.
    private func drawHoneycomb() {
        let locked = sync.localCoherence
        for (i, cell) in grid.enumerated() {
            let phase = sync.phases[i]
            let agree = max(0, (locked[i] - 0.5) * 2)
            fill(Color(hue: phase / .tau, saturation: 0.15 + 0.85 * agree, brightness: 0.45 + 0.5 * agree))
            drawPolygon(cell.corners)
        }
    }

    /// The phases on a circle, and the order parameter as an arrow from its center.
    private func drawWheel() {
        let c = Vector2(width - 170, height - 190)
        let r = 110.0
        noFill()
        stroke(Color(white: 1, alpha: 0.18))
        strokeWeight(1.5)
        drawCircle(center: c, radius: r)
        noStroke()
        fill(glow.withAlpha(0.6))
        for phase in sync.phases {
            drawCircle(c.x + cos(phase) * r, c.y + sin(phase) * r, 2.5)
        }
        let tip = Vector2(c.x + cos(sync.meanPhase) * r * sync.coherence,
                          c.y + sin(sync.meanPhase) * r * sync.coherence)
        stroke(.white)
        strokeWeight(3)
        strokeCap(.round)
        drawLine(c, tip)
        noStroke()
        fill(.white)
        drawCircle(center: tip, radius: 5)
    }
}
