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
@main
final class Fireflies: Sketch {

    /// How hard the crowd pulls on each firefly's phase (K, per second).
    @Param("Coupling", 0 ... 4, icon: "link") var coupling = 2.0
    /// The standard deviation of the natural frequencies, in radians per second;
    /// 0 makes every firefly the same, and a wide spread needs a stronger pull.
    @Param("Spread", 0 ... 1.5, icon: "waveform.path") var spread = 0.5

    private var sync: Kuramoto!
    private var spots: [Vector2] = []
    private var madeSpread = -1.0
    private let count = 400
    private let glow = Color(hex: 0xE9FF7C)

    override func setup() {
        remake()
    }

    override func draw() {
        if spread != madeSpread { remake() }
        sync.coupling = coupling
        sync.advance()

        background(Color(hex: 0x06100E))
        noStroke()
        for (i, phase) in sync.phases.enumerated() {
            // A flash rather than a sine: the glow rises sharply once a turn.
            let lit = pow((1 + cos(phase)) / 2, 4)
            fill(glow.withAlpha(lit * 0.22))
            drawCircle(center: spots[i], radius: 16)
            fill(glow.withAlpha(0.06 + lit * 0.94))
            drawCircle(center: spots[i], radius: 3.5)
        }
        drawWheel()
        drawCaption(String(format: "Kuramoto · r = %.2f · coupling %.1f, critical %.2f · drag the sliders",
                           sync.coherence, coupling, sync.criticalCoupling))
    }

    /// A fresh crowd at the current spread. The run's variation places the
    /// meadow, kept clear of the wheel's corner; the crowd itself keeps one seed,
    /// so its flashes fall on the same frames in every run.
    private func remake() {
        randomSeed(variation)
        let wheel = Vector2(width - 170, height - 190)
        spots = []
        while spots.count < count {
            let spot = Vector2(random(40, width - 40), random(40, height - 120))
            if spot.distance(to: wheel) > 150 { spots.append(spot) }
        }
        sync = Kuramoto(count: count, coupling: coupling, frequency: 3, spread: spread, seed: 7)
        madeSpread = spread
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
