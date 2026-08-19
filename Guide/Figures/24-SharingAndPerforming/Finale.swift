// figure: frame=200
//
// Guide payoff (Chapter 24): the live-coded set's final state, the chain all
// five evaluations built. Drifting oscillator bands folded five ways, melted
// by noise, posterized to a screen-print, set slowly spinning through the
// color wheel. Every value is animated, so the piece never sits still.
import Ollin

final class Finale: Sketch {
    override func draw() {
        drawVisual(
            .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
                .kaleidoscope(5)
                .displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)
                .posterized(bins: 6, gamma: 0.75)
                .rotated(time * 0.03)
                .colorCycled(time * 0.04)
        )
    }
}
